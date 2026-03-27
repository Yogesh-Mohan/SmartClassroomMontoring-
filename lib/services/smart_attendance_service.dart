import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:async/async.dart';
import 'package:geolocator/geolocator.dart';

class AttendanceError implements Exception {
  final String code;
  final String message;

  AttendanceError(this.code, this.message);

  @override
  String toString() => 'AttendanceError($code): $message';
}

class AttendanceSession {
  final String id;
  final String code;
  final String period;
  final String date;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final String classroomPolygon;

  const AttendanceSession({
    required this.id,
    required this.code,
    required this.period,
    required this.date,
    required this.status,
    required this.classroomPolygon,
    required this.startedAt,
    required this.expiresAt,
  });

  Duration get timeLeft {
    if (expiresAt == null) return Duration.zero;
    final left = expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isActive {
    if (status != 'active') return false;
    if (expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt!);
  }

  factory AttendanceSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final started = data['startedAt'];
    final expires = data['expiresAt'];

    return AttendanceSession(
      id: doc.id,
      code: (data['code'] ?? '').toString(),
      period: (data['period'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      status: (data['status'] ?? 'expired').toString(),
      classroomPolygon: (data['classroomPolygon'] ?? '').toString(),
      startedAt: started is Timestamp ? started.toDate() : null,
      expiresAt: expires is Timestamp ? expires.toDate() : null,
    );
  }
}

class StudentSubmitResult {
  final bool success;
  final String code;
  final String message;

  const StudentSubmitResult({
    required this.success,
    required this.code,
    required this.message,
  });
}

class AttendanceSummary {
  final int presentCount;
  final int absentCount;

  const AttendanceSummary({
    required this.presentCount,
    required this.absentCount,
  });
}

class StudentAttendanceView {
  final String uid;
  final String name;
  final String status;
  final DateTime? timestamp;
  final bool manual;

  const StudentAttendanceView({
    required this.uid,
    required this.name,
    required this.status,
    required this.timestamp,
    required this.manual,
  });
}

class SmartAttendanceService {
  SmartAttendanceService._();

  static final SmartAttendanceService instance = SmartAttendanceService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Duration sessionDuration = Duration(minutes: 10);
  static const String _defaultClassPolygon =
      '[[11.055451807408986,78.04807911],[11.055355016363238,78.048391280139057],[11.055254737351877,78.048360760439948],[11.055352400389028,78.048053819466048],[11.05544744745197,78.048081723190947]]';
  static const Map<int, String> _dayNames = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  Iterable<String> _periodLookupKeys(String period) {
    final raw = period.trim();
    if (raw.isEmpty) return const <String>[];

    final keys = <String>{raw};
    final number = RegExp(r'(\d+)').firstMatch(raw)?.group(1);
    if (number != null) {
      keys.add('Period $number');
      keys.add('period $number');
      keys.add('peroid $number');
      keys.add('Peroid $number');
      keys.add('P$number');
    }
    return keys;
  }

  String _normalizePeriodLabel(String rawPeriod) {
    final trimmed = rawPeriod.trim();
    if (trimmed.isEmpty) return trimmed;
    final number = RegExp(r'(\d+)').firstMatch(trimmed)?.group(1);
    if (number != null) return 'Period $number';
    return trimmed;
  }

  Future<String?> getCurrentClassPeriod() async {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final dayName = _dayNames[now.weekday] ?? 'Monday';
    final lowerDay = dayName.toLowerCase();

    QuerySnapshot<Map<String, dynamic>> allClasses;
    try {
      allClasses = await _db.collection('timetables').get();
    } catch (_) {
      return null;
    }

    for (final classDoc in allClasses.docs) {
      QuerySnapshot<Map<String, dynamic>> periods;
      try {
        periods = await _db
            .collection('timetables')
            .doc(classDoc.id)
            .collection(dayName)
            .get();

        if (periods.docs.isEmpty && dayName != lowerDay) {
          periods = await _db
              .collection('timetables')
              .doc(classDoc.id)
              .collection(lowerDay)
              .get();
        }
      } catch (_) {
        continue;
      }

      if (periods.docs.isEmpty) continue;

      for (final periodDoc in periods.docs) {
        final data = periodDoc.data();
        final monitoringRaw = data['monitoring'] ?? data['montoring'];
        final monitoring =
            monitoringRaw == true || monitoringRaw.toString() == 'true';
        final start = (data['startTime'] as num?)?.toInt() ?? 0;
        final end = (data['endTime'] as num?)?.toInt() ?? 0;
        final inRange = currentMinutes >= start && currentMinutes < end;

        if (inRange && monitoring) {
          return _normalizePeriodLabel(periodDoc.id);
        }
      }
    }

    return null;
  }

  String todayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _sessionId(String period, String date) {
    final cleaned = period.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${date}_$cleaned';
  }

  String _recordId(String uid, String period, String date) {
    final cleaned = period.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${date}_${cleaned}_$uid';
  }

  String _randomCode() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  Future<void> assertAdmin() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AttendanceError('unauthenticated', 'Please login to continue.');
    }

    final adminDoc = await _db.collection('admins').doc(user.uid).get();
    if (adminDoc.exists) return;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final role = (userDoc.data()?['role'] ?? '').toString().toLowerCase();
    if (role != 'admin') {
      throw AttendanceError(
        'permission-denied',
        'Only admin can create attendance sessions.',
      );
    }
  }

  Future<AttendanceSession> startOrReuseSession({
    required String period,
    required String classroomPolygon,
  }) async {
    await assertAdmin();

    final user = _auth.currentUser;
    if (user == null) {
      throw AttendanceError('unauthenticated', 'Please login to continue.');
    }

    final date = todayDateKey();
    final sessionDocId = _sessionId(period, date);
    final sessionRef = _db.collection('attendance_sessions').doc(sessionDocId);

    return _db.runTransaction((tx) async {
      final existing = await tx.get(sessionRef);
      if (existing.exists) {
        final session = AttendanceSession.fromDoc(existing);
        if (session.isActive) {
          final incomingPolygon = classroomPolygon.trim();
          if (incomingPolygon.isNotEmpty &&
              incomingPolygon != session.classroomPolygon.trim()) {
            tx.set(sessionRef, {
              'classroomPolygon': incomingPolygon,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            return AttendanceSession(
              id: session.id,
              code: session.code,
              period: session.period,
              date: session.date,
              status: session.status,
              classroomPolygon: incomingPolygon,
              startedAt: session.startedAt,
              expiresAt: session.expiresAt,
            );
          }

          return session;
        }
      }

      final now = DateTime.now();
      final expiresAt = now.add(sessionDuration);
      final generatedCode = _randomCode();

      tx.set(sessionRef, {
        'period': period,
        'date': date,
        'code': generatedCode,
        'status': 'active',
        'classroomPolygon': classroomPolygon,
        'startedAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'createdBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return AttendanceSession(
        id: sessionDocId,
        code: generatedCode,
        period: period,
        date: date,
        status: 'active',
        classroomPolygon: classroomPolygon,
        startedAt: now,
        expiresAt: expiresAt,
      );
    });
  }

  Stream<AttendanceSession?> watchSession({
    required String period,
    String? date,
  }) {
    final chosenDate = date ?? todayDateKey();
    final sessionId = _sessionId(period, chosenDate);

    return _db
        .collection('attendance_sessions')
        .doc(sessionId)
        .snapshots()
        .map((doc) => doc.exists ? AttendanceSession.fromDoc(doc) : null);
  }

  Future<void> markSessionExpired({required String sessionId}) async {
    await assertAdmin();
    await _db.collection('attendance_sessions').doc(sessionId).set({
      'status': 'expired',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AttendanceSession?> getActiveSessionByCode({
    required String period,
    required String date,
    required String code,
  }) async {
    final sessionId = _sessionId(period, date);
    final doc = await _db.collection('attendance_sessions').doc(sessionId).get();
    if (!doc.exists) return null;

    final session = AttendanceSession.fromDoc(doc);
    if (session.code != code) return null;
    return session;
  }

  Future<String> getClassroomPolygonForPeriod(String period) async {
    String? pickPolygon(QuerySnapshot<Map<String, dynamic>> snap) {
      for (final doc in snap.docs) {
        final polygon = _extractPolygonRaw(doc.data());
        if (polygon.trim().isNotEmpty) {
          return polygon;
        }
      }
      return null;
    }

    for (final key in _periodLookupKeys(period)) {
      final doc = await _db.collection('classroom_geofences').doc(key).get();
      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        final polygon = _extractPolygonRaw(data);
        if (polygon.trim().isNotEmpty) return polygon;
      }
    }

    // Support docs where period mapping is saved in fields, not doc ID.
    for (final key in _periodLookupKeys(period)) {
      final byPeriodField = await _db
          .collection('classroom_geofences')
          .where('period', isEqualTo: key)
          .limit(5)
          .get();
      final polygon = pickPolygon(byPeriodField);
      if (polygon != null) return polygon;

      final byPeriodsArray = await _db
          .collection('classroom_geofences')
          .where('periods', arrayContains: key)
          .limit(5)
          .get();
      final polygonFromArray = pickPolygon(byPeriodsArray);
      if (polygonFromArray != null) return polygonFromArray;
    }

    final fallback = await _db
        .collection('classroom_geofences')
        .doc('default')
        .get();
    if (fallback.exists) {
      final polygon =
          _extractPolygonRaw(fallback.data() ?? <String, dynamic>{});
      if (polygon.trim().isNotEmpty) return polygon;
    }

    // If geofence docs are classroom-name based, use the first valid polygon.
    final anyDoc = await _db.collection('classroom_geofences').limit(20).get();
    final anyPolygon = pickPolygon(anyDoc);
    if (anyPolygon != null) return anyPolygon;

    return _defaultClassPolygon;
  }

  Future<StudentSubmitResult> submitAttendance({
    required String code,
    required String period,
    required String studentName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const StudentSubmitResult(
        success: false,
        code: 'unauthenticated',
        message: 'Please login first.',
      );
    }

    final date = todayDateKey();

    try {
      final session = await getActiveSessionByCode(
        period: period,
        date: date,
        code: code.trim(),
      );

      if (session == null) {
        return const StudentSubmitResult(
          success: false,
          code: 'invalid-code',
          message: 'Invalid code',
        );
      }

      final now = DateTime.now();
      if (session.status != 'active') {
        return const StudentSubmitResult(
          success: false,
          code: 'code-expired',
          message: 'Code expired',
        );
      }
      if (session.expiresAt == null || now.isAfter(session.expiresAt!)) {
        await _db.collection('attendance_sessions').doc(session.id).set({
          'status': 'expired',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return const StudentSubmitResult(
          success: false,
          code: 'code-expired',
          message: 'Code expired',
        );
      }

      final duplicateId = _recordId(user.uid, period, date);
      final existing =
          await _db.collection('attendance_records').doc(duplicateId).get();
      if (existing.exists) {
        return const StudentSubmitResult(
          success: false,
          code: 'already-submitted',
          message: 'Already submitted',
        );
      }

      final inGeofence = await _isStudentInsidePolygon(session.classroomPolygon);
      if (!inGeofence) {
        return const StudentSubmitResult(
          success: false,
          code: 'outside-classroom',
          message: 'Outside classroom',
        );
      }

      await _db.collection('attendance_records').doc(duplicateId).set({
        'sessionId': session.id,
        'studentUID': user.uid,
        'name': studentName,
        'period': period,
        'date': date,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'present',
        'manual': false,
      });

      return const StudentSubmitResult(
        success: true,
        code: 'ok',
        message: 'Attendance marked',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        return const StudentSubmitResult(
          success: false,
          code: 'no-internet',
          message: 'No internet',
        );
      }

      return StudentSubmitResult(
        success: false,
        code: 'firestore-failure',
        message: 'Firestore failure',
      );
    } on AttendanceError catch (e) {
      return StudentSubmitResult(success: false, code: e.code, message: e.message);
    } catch (_) {
      return const StudentSubmitResult(
        success: false,
        code: 'unknown',
        message: 'Something went wrong',
      );
    }
  }

  Stream<List<StudentAttendanceView>> watchAttendanceForSession({
    required String period,
    String? date,
  }) {
    final chosenDate = date ?? todayDateKey();

    final studentsStream =
        _db.collection('students').snapshots().map((snapshot) => snapshot.docs);
    final recordsStream = _db
        .collection('attendance_records')
        .where('period', isEqualTo: period)
        .where('date', isEqualTo: chosenDate)
        .snapshots()
        .map((snapshot) => snapshot.docs);

    return StreamZip([studentsStream, recordsStream]).map((parts) {
      final studentDocs = parts[0] as List;
      final recordDocs = parts[1] as List;

      final recordByUid = <String, Map<String, dynamic>>{};
      for (final record in recordDocs) {
        final data = record.data();
        final uid = (data['studentUID'] ?? '').toString();
        if (uid.isEmpty) continue;
        recordByUid[uid] = data;
      }

      final rows = <StudentAttendanceView>[];
      for (final student in studentDocs) {
        final data = student.data();
        final uid = (data['uid'] ?? student.id).toString();
        final name = (data['name'] ?? data['studentName'] ?? 'Student').toString();

        final record = recordByUid[uid];
        final rawTs = record?['timestamp'];

        rows.add(
          StudentAttendanceView(
            uid: uid,
            name: name,
            status: (record?['status'] ?? 'absent').toString(),
            timestamp: rawTs is Timestamp ? rawTs.toDate() : null,
            manual: (record?['manual'] ?? false) == true,
          ),
        );
      }

      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return rows;
    });
  }

  Future<void> manualOverride({
    required String studentUid,
    required String studentName,
    required String period,
    required String status,
  }) async {
    await assertAdmin();
    final date = todayDateKey();
    final recordId = _recordId(studentUid, period, date);

    await _db.collection('attendance_records').doc(recordId).set({
      'studentUID': studentUid,
      'name': studentName,
      'period': period,
      'date': date,
      'timestamp': FieldValue.serverTimestamp(),
      'status': status,
      'manual': true,
    }, SetOptions(merge: true));
  }

  AttendanceSummary buildSummary(List<StudentAttendanceView> list) {
    var present = 0;
    for (final item in list) {
      if (item.status == 'present') present++;
    }
    return AttendanceSummary(
      presentCount: present,
      absentCount: max(0, list.length - present),
    );
  }

  Future<bool> _isStudentInsidePolygon(String polygonRaw) async {
    final points = _parsePolygon(polygonRaw);
    if (points.length < 3) {
      throw AttendanceError(
        'geofence-missing',
        'Classroom polygon is not configured correctly.',
      );
    }

    final swappedPoints = points
        .map((p) => _LatLng(p.lng, p.lat))
        .toList(growable: false);

    final permission = await _ensureLocationPermission();
    if (!permission) {
      throw AttendanceError('gps-denied', 'GPS permission denied');
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw AttendanceError('gps-disabled', 'Please enable location services');
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      throw AttendanceError('gps-timeout', 'Unable to get GPS location in time');
    }

    final insideDirect = _pointInPolygon(
      position.latitude,
      position.longitude,
      points,
    );
    if (insideDirect) return true;

    // Support Firestore polygons stored as [lng, lat] by trying swapped coords.
    return _pointInPolygon(
      position.latitude,
      position.longitude,
      swappedPoints,
    );
  }

  Future<bool> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) return false;
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  List<_LatLng> _parsePolygon(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final decoded = jsonDecode(trimmed);
      final out = _extractCoordinates(decoded);
      if (out.isNotEmpty) return out;
    } catch (_) {
      // Supports fallback plain-text polygon formats.
    }

    final out = <_LatLng>[];
    final chunks = trimmed.split(';');
    for (final chunk in chunks) {
      final pair = chunk.split(',');
      if (pair.length < 2) continue;
      final lat = double.tryParse(pair[0].trim());
      final lng = double.tryParse(pair[1].trim());
      if (lat != null && lng != null) {
        out.add(_LatLng(lat, lng));
      }
    }

    return out;
  }

  String _extractPolygonRaw(Map<String, dynamic> data) {
    const candidateKeys = <String>[
      'polygon',
      'geojson',
      'geoJson',
      'classroomPolygon',
      'geometry',
      'coordinates',
    ];

    for (final key in candidateKeys) {
      if (!data.containsKey(key)) continue;
      final normalized = _normalizePolygonValue(data[key]);
      if (normalized.isNotEmpty) return normalized;
    }

    return '';
  }

  String _normalizePolygonValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();

    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString().trim();
    }
  }

  List<_LatLng> _extractCoordinates(dynamic source) {
    if (source is List && source.isNotEmpty && source.first is num) {
      // Single pair like [lat, lng] or [lng, lat] is not a polygon.
      return const [];
    }

    if (source is List) {
      final directPairs = <_LatLng>[];
      var allPairs = true;
      for (final item in source) {
        if (item is List && item.length >= 2 && item[0] is num && item[1] is num) {
          directPairs.add(_LatLng((item[0] as num).toDouble(), (item[1] as num).toDouble()));
        } else {
          allPairs = false;
          break;
        }
      }
      if (allPairs && directPairs.length >= 3) return directPairs;

      // Nested list (Polygon rings / MultiPolygon): use first valid ring.
      for (final item in source) {
        final extracted = _extractCoordinates(item);
        if (extracted.length >= 3) return extracted;
      }
      return const [];
    }

    if (source is Map) {
      final map = source.cast<String, dynamic>();

      final lat = map['lat'];
      final lng = map['lng'];
      if (lat is num && lng is num) {
        return [_LatLng(lat.toDouble(), lng.toDouble())];
      }

      final features = map['features'];
      if (features != null) {
        final extracted = _extractCoordinates(features);
        if (extracted.length >= 3) return extracted;
      }

      final geometry = map['geometry'];
      if (geometry != null) {
        final extracted = _extractCoordinates(geometry);
        if (extracted.length >= 3) return extracted;
      }

      final coordinates = map['coordinates'];
      if (coordinates != null) {
        final extracted = _extractCoordinates(coordinates);
        if (extracted.length >= 3) return extracted;
      }
    }

    return const [];
  }

  bool _pointInPolygon(double lat, double lng, List<_LatLng> polygon) {
    var inside = false;
    var j = polygon.length - 1;

    for (var i = 0; i < polygon.length; i++) {
      final yi = polygon[i].lat;
      final xi = polygon[i].lng;
      final yj = polygon[j].lat;
      final xj = polygon[j].lng;

      final intersects = ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / ((yj - yi) + 0.00000001) + xi);
      if (intersects) inside = !inside;
      j = i;
    }

    return inside;
  }
}

class _LatLng {
  final double lat;
  final double lng;

  const _LatLng(this.lat, this.lng);
}
