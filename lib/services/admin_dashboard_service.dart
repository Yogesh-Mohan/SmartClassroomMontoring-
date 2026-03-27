import 'dart:async';
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminStudentRow {
  final String uid;
  final String name;
  final String regNo;
  final String classLabel;

  const AdminStudentRow({
    required this.uid,
    required this.name,
    required this.regNo,
    required this.classLabel,
  });
}

class AdminAlertRow {
  final String name;
  final String regNo;
  final String period;
  final DateTime timestamp;
  final int secondsUsed;

  const AdminAlertRow({
    required this.name,
    required this.regNo,
    required this.period,
    required this.timestamp,
    this.secondsUsed = 0,
  });
}

class AdminTopViolator {
  final String name;
  final int count;
  const AdminTopViolator({required this.name, required this.count});
}

class AdminDailyViolation {
  final DateTime date;
  final int count;          // total violations that day
  final String topName;     // first name of top violator ('' if none)
  const AdminDailyViolation({
    required this.date,
    required this.count,
    required this.topName,
  });
}

class AdminDashboardService {
  final FirebaseFirestore _db;

  AdminDashboardService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  String _todayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${y}_${m}_$d';
  }

  Query<Map<String, dynamic>> _todayAttendanceQuery() {
    return _db.collection('attendance').where('date', isEqualTo: _todayDateKey());
  }

  Query<Map<String, dynamic>> _activeSessionsQuery() {
    return _db.collection('student_sessions').where('loginState', isEqualTo: 1);
  }


  String _displayName(Map<String, dynamic> data) {
    return (data['name'] ?? data['studentName'] ?? 'Unknown').toString().trim();
  }

  String _displayRegNo(Map<String, dynamic> data) {
    return (data['regNo'] ??
            data['registrationNumber'] ??
            data['studentId'] ??
            data['rollNo'] ??
            '')
        .toString()
        .trim();
  }

  String _displayClass(Map<String, dynamic> data) {
    return (data['className'] ??
            data['class'] ??
            data['section'] ??
            data['department'] ??
            data['course'] ??
            '-')
        .toString()
        .trim();
  }

        String _attendanceUid(String docId, Map<String, dynamic> row) {
          final direct =
              (row['studentUID'] ?? row['studentUid'] ?? row['uid'] ?? '')
                  .toString()
                  .trim();
          if (direct.isNotEmpty) return direct;

          final normalizedDocId = docId.trim();
          final suffixPattern = RegExp(r'_[0-9]{4}_[0-9]{2}_[0-9]{2}$');
          if (suffixPattern.hasMatch(normalizedDocId) && normalizedDocId.length > 11) {
            return normalizedDocId.substring(0, normalizedDocId.length - 11);
          }
          return normalizedDocId;
        }

  String _sessionUid(String docId, Map<String, dynamic> row) {
    final direct = (row['uid'] ?? row['studentUID'] ?? row['studentUid'] ?? '')
        .toString()
        .trim();
    return direct.isNotEmpty ? direct : docId.trim();
  }

  Stream<List<AdminStudentRow>> streamTotalStudentsList() {
    return _db.collection('students').snapshots().map((snap) {
      final rows = snap.docs
          .map((doc) {
            final data = doc.data();
            final uid = (data['uid'] ?? doc.id).toString().trim();
            return AdminStudentRow(
              uid: uid,
              name: _displayName(data),
              regNo: _displayRegNo(data),
              classLabel: _displayClass(data),
            );
          })
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return rows;
    });
  }

  Stream<List<AdminStudentRow>> streamPresentTodayList() {
    final attendanceTrigger = _todayAttendanceQuery().snapshots().map((_) {});
    final studentTrigger = _db.collection('students').snapshots().map((_) {});
    final sessionTrigger = _activeSessionsQuery().snapshots().map((_) {});

    return StreamGroup.merge([attendanceTrigger, studentTrigger, sessionTrigger]).asyncMap((_) async {
      final attendanceSnap = await _todayAttendanceQuery().get();
      final studentsSnap = await _db.collection('students').get();
      final sessionSnap = await _activeSessionsQuery().get();

      // Build student profile lookup by UID
      final studentByUid = <String, Map<String, dynamic>>{};
      for (final doc in studentsSnap.docs) {
        final data = doc.data();
        final uid = (data['uid'] ?? doc.id).toString().trim();
        if (uid.isNotEmpty) studentByUid[uid] = {'id': doc.id, ...data};
      }

      final unique = <String, AdminStudentRow>{};

      // Explicit logged-in sessions are always considered present.
      for (final doc in sessionSnap.docs) {
        final row = doc.data();
        final uid = _sessionUid(doc.id, row);
        if (uid.isEmpty) continue;
        final profile = studentByUid[uid] ?? row;
        unique[uid] = AdminStudentRow(
          uid: uid,
          name: _displayName(profile),
          regNo: _displayRegNo(profile),
          classLabel: _displayClass(profile),
        );
      }

      for (final doc in attendanceSnap.docs) {
        final row = doc.data();
        // Only include students who are currently inside (no logoutTime yet)
        if (row['logoutTime'] != null) continue;
        final uid = _attendanceUid(doc.id, row);
        if (uid.isEmpty) continue;

        // Merge attendance + student profile to get full details
        final profile = studentByUid[uid] ?? row;
        unique[uid] = AdminStudentRow(
          uid: uid,
          name: _displayName(profile),
          regNo: _displayRegNo(profile),
          classLabel: _displayClass(profile),
        );
      }

      return unique.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  Stream<List<AdminStudentRow>> streamNotLoggedInTodayList() {
    final studentTrigger = _db.collection('students').snapshots().map((_) {});
    final attendanceTrigger = _todayAttendanceQuery().snapshots().map((_) {});
    final sessionTrigger = _activeSessionsQuery().snapshots().map((_) {});

    return StreamGroup.merge([studentTrigger, attendanceTrigger, sessionTrigger]).asyncMap((_) async {
      final studentsSnap = await _db.collection('students').get();
      final attendanceSnap = await _todayAttendanceQuery().get();
      final sessionSnap = await _activeSessionsQuery().get();

      final loggedUids = <String>{};
      for (final doc in attendanceSnap.docs) {
        // Only treat as "currently present" if they haven't logged out yet
        if (doc.data()['logoutTime'] != null) continue;
        final uid = _attendanceUid(doc.id, doc.data());
        if (uid.isNotEmpty) loggedUids.add(uid);
      }

      for (final doc in sessionSnap.docs) {
        final uid = _sessionUid(doc.id, doc.data());
        if (uid.isNotEmpty) loggedUids.add(uid);
      }

      final notLogged = studentsSnap.docs
          .where((doc) {
            final uid = (doc.data()['uid'] ?? doc.id).toString().trim();
            return uid.isNotEmpty && !loggedUids.contains(uid);
          })
          .map((doc) {
            final data = doc.data();
            return AdminStudentRow(
              uid: (data['uid'] ?? doc.id).toString().trim(),
              name: _displayName(data),
              regNo: _displayRegNo(data),
              classLabel: _displayClass(data),
            );
          })
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      return notLogged;
    });
  }

  Stream<List<AdminAlertRow>> streamTodayAlertsList() {
    // Full calendar-day window (midnight → now)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _db
        .collection('violations')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              final ts = data['timestamp'];
              final time = ts is Timestamp ? ts.toDate() : DateTime.now();
              return AdminAlertRow(
                name: _displayName(data),
                regNo: _displayRegNo(data),
                period: (data['period'] ?? 'Unknown').toString(),
                timestamp: time,
              );
            }).toList());
  }

  /// Last 3 unique students with alerts today (home screen Recent Alerts).
  Stream<List<AdminAlertRow>> streamRecentUniqueAlerts() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _db
        .collection('violations')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) {
      final seen = <String>{};
      final out = <AdminAlertRow>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final nameKey = _displayName(data).trim().toLowerCase();
        if (seen.contains(nameKey)) continue;
        seen.add(nameKey);
        final ts = data['timestamp'];
        final time = ts is Timestamp ? ts.toDate() : DateTime.now();
        out.add(AdminAlertRow(
          name: _displayName(data),
          regNo: _displayRegNo(data),
          period: (data['period'] ?? 'Unknown').toString(),
          timestamp: time,
        ));
        if (out.length == 3) break;
      }
      return out;
    });
  }

  /// Violations screen — last 48 hours rolling window.
  Stream<List<AdminAlertRow>> streamLast2DaysAlertsList() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    return _db
        .collection('violations')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              final ts = data['timestamp'];
              final time = ts is Timestamp ? ts.toDate() : DateTime.now();
              return AdminAlertRow(
                name: _displayName(data),
                regNo: _displayRegNo(data),
                period: (data['period'] ?? 'Unknown').toString(),
                timestamp: time,
                secondsUsed: (data['secondsUsed'] as num?)?.toInt() ?? 0,
              );
            }).toList());
  }

  /// Top students by phone-usage violation count today (for home bar chart).
  Stream<List<AdminTopViolator>> streamTopViolators({int limit = 5}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _db
        .collection('violations')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .snapshots()
        .map((snap) {
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final name = _displayName(doc.data()).trim();
        if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted
          .take(limit)
          .map((e) => AdminTopViolator(name: e.key, count: e.value))
          .toList();
    });
  }

  /// Last 7 days: per-day total violations + top violator name.
  Stream<List<AdminDailyViolation>> streamWeeklyViolationChart() {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    return _db
        .collection('violations')
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((snap) {
      // dayKey -> studentName -> count
      final dayMap = <String, Map<String, int>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        if (ts is! Timestamp) continue;
        final dt = ts.toDate().toLocal();
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        final name = _displayName(data).trim();
        dayMap[key] ??= {};
        dayMap[key]![name] = (dayMap[key]![name] ?? 0) + 1;
      }

      return List.generate(7, (i) {
        final day = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: 6 - i));
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final studentCounts = dayMap[key] ?? {};
        final total = studentCounts.values.fold(0, (a, b) => a + b);
        final topName = studentCounts.isEmpty
            ? ''
            : (studentCounts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key
                .split(' ')
                .first;
        return AdminDailyViolation(date: day, count: total, topName: topName);
      });
    });
  }

  Stream<int> streamTotalStudentsCount() {
    return streamTotalStudentsList().map((rows) => rows.length);
  }

  Stream<int> streamPresentTodayCount() {
    return streamPresentTodayList().map((rows) => rows.length);
  }

  Stream<int> streamNotLoggedInTodayCount() {
    return streamNotLoggedInTodayList().map((rows) => rows.length);
  }

  Stream<int> streamTodayAlertsCount() {
    return streamTodayAlertsList().map((rows) => rows.length);
  }
}