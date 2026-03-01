import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// AttendanceService
///
/// Handles two responsibilities:
///   1. [createAttendance]  — Called on first morning login.
///      Creates attendance/{studentUID_YYYY_MM_DD} if it doesn't already exist.
///
///   2. [handleLogout]      — Called when student taps Logout.
///      Checks whether the current period is the LAST period of the day.
///        • Not last period → block logout, log to logout_attempts.
///        • Last period     → allow logout, update attendance doc with logoutTime.
///
/// Timetable structure (mirrors TimetableMonitor):
///   timetables/{classId}/{dayName}/{periodDocId}
///     fields: startTime (int, minutes), endTime (int, minutes), monitoring (bool)
class AttendanceService {
  AttendanceService._();
  static final AttendanceService instance = AttendanceService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Day helpers ────────────────────────────────────────────────────────────

  static const _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  String _todayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${y}_${m}_$d'; // e.g. 2026_02_27
  }

  String _currentDayName() =>
      _dayNames[DateTime.now().weekday] ?? 'Monday';

  // ── 1. CREATE ATTENDANCE ──────────────────────────────────────────────────

  /// Call this immediately after the student's first login each day.
  ///
  /// [studentData] — the map fetched from Firestore `students` collection.
  ///
  /// Returns `true` if a new attendance document was created,
  ///         `false` if the document already existed (duplicate guard),
  ///         throws on Firestore errors.
  Future<bool> createAttendance({
    required Map<String, dynamic> studentData,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user found.');

    final uid       = user.uid;
    final dateKey   = _todayDateKey();
    final docId     = '${uid}_$dateKey';
    final docRef    = _db.collection('attendance').doc(docId);

    try {
      // ── Duplicate guard ──────────────────────────────────────────────
      final existing = await docRef.get();
      if (existing.exists) {
        debugPrint('[Attendance] Doc $docId already exists — skipping create.');
        return false;
      }

      // ── Create attendance record ─────────────────────────────────────
      await docRef.set({
        'studentUID':  uid,
        'studentName': studentData['name']  ??
                       studentData['studentName'] ?? '',
        'regNo':       studentData['regNo'] ??
                       studentData['registrationNumber'] ?? '',
        'date':        dateKey,
        'loginTime':   FieldValue.serverTimestamp(),
        // NOTE: logoutTime and logoutType are intentionally NOT set here.
      });

      debugPrint('[Attendance] Created: $docId');
      return true;
    } catch (e, st) {
      debugPrint('[Attendance] createAttendance error: $e\n$st');
      rethrow;
    }
  }

  // ── 2. HANDLE LOGOUT ──────────────────────────────────────────────────────

  /// Call this when the student taps Logout.
  ///
  /// [studentData]  — the map fetched from Firestore `students` collection.
  /// [classId]      — the student's class/batch ID used to look up the
  ///                  timetable (e.g. "CSE_AI_2025").
  ///
  /// Returns a [LogoutResult] describing what happened.
  Future<LogoutResult> handleLogout({
    required Map<String, dynamic> studentData,
    required String classId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user found.');

    final uid          = user.uid;
    final studentName  = (studentData['name'] ??
                          studentData['studentName'] ?? '') as String;
    final regNo        = (studentData['regNo'] ??
                          studentData['registrationNumber'] ?? '') as String;

    try {
      // ── Fetch today's timetable ──────────────────────────────────────
        final dayName  = _currentDayName();
        final lowerDay = dayName.toLowerCase();
        final classIdNormalized = classId.trim();

        final periods = classIdNormalized.isEmpty
          ? <_PeriodInfo>[]
          : await _fetchPeriods(classIdNormalized, dayName, lowerDay);

      // ── Determine current period & last period ───────────────────────
      final now            = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      _PeriodInfo? currentPeriod;
      _PeriodInfo? lastPeriod; // period with highest endTime

      for (final p in periods) {
        // Track last period (highest endTime across all periods)
        if (lastPeriod == null || p.endTime > lastPeriod.endTime) {
          lastPeriod = p;
        }
        // Find matching current period
        if (currentMinutes >= p.startTime && currentMinutes < p.endTime) {
          currentPeriod = p;
        }
      }

      debugPrint('[Attendance] currentMinutes=$currentMinutes, '
          'currentPeriod=${currentPeriod?.id}, lastPeriod=${lastPeriod?.id}');

      // ── If no timetable found, allow logout gracefully ─────────────────
      if (periods.isEmpty) {
        debugPrint('[Attendance] No timetable found for ${classIdNormalized.isEmpty ? 'unknown class' : classIdNormalized} — allowing logout.');
        final dateKey2 = _todayDateKey();
        final docId2   = '${uid}_$dateKey2';
        await _db.collection('attendance').doc(docId2).set({
          'studentUID': uid,
          'studentName': studentName,
          'regNo': regNo,
          'date': dateKey2,
          'logoutTime': FieldValue.serverTimestamp(),
          'logoutType': 'normal',
        }, SetOptions(merge: true));
        // Notify admins even when no timetable is configured.
        unawaited(_notifyAdmins(
          title: '✅ Student Logged Out',
          body:  '$studentName ($regNo) has logged out successfully.',
          data:  {'type': 'student_logout', 'studentName': studentName, 'regNo': regNo},
        ));
        return LogoutResult(
          allowed:       true,
          reason:        'Logout successful.',
          currentPeriod: '',
        );
      }

      // ── Decision ─────────────────────────────────────────────────────
      final isLastPeriod = currentPeriod != null &&
          lastPeriod != null &&
          currentPeriod.id == lastPeriod.id;

      if (!isLastPeriod) {
        // ── BLOCK LOGOUT: log the early attempt ─────────────────────
        final periodLabel = currentPeriod?.id ?? 'unknown';

        // Attempt to log — silently ignore if rules not deployed yet.
        try {
          await _db.collection('logout_attempts').add({
            'studentUID':   uid,
            'studentName':  studentName,
            'regNo':        regNo,
            'period':       periodLabel,
            'attemptTime':  FieldValue.serverTimestamp(),
            'type':         'early_logout',
          });
        } catch (e) {
          debugPrint('[Attendance] logout_attempts write failed (check rules deployed): $e');
        }

        // Notify all admins about early logout attempt.
        final displayPeriod = periodLabel == 'unknown' ? 'Outside Class Hours' : periodLabel;
        unawaited(_notifyAdmins(
          title: '⚠️ Early Logout Attempt',
          body:  '$studentName ($regNo) tried to logout during $displayPeriod.',
          data:  {
            'type':        'early_logout',
            'studentName': studentName,
            'regNo':       regNo,
            'period':      displayPeriod,
          },
        ));

        debugPrint('[Attendance] Early logout blocked. Period: $periodLabel');

        return LogoutResult(
          allowed: false,
          reason:  currentPeriod != null
              ? 'You are in $periodLabel. Logout is only allowed after the last period.'
              : 'No active period found. Logout is blocked outside class hours.',
          currentPeriod: periodLabel,
        );
      }

      // ── ALLOW LOGOUT: update attendance document ─────────────────
      final dateKey = _todayDateKey();
      final docId   = '${uid}_$dateKey';
      final docRef  = _db.collection('attendance').doc(docId);

      await docRef.set({
        'studentUID': uid,
        'studentName': studentName,
        'regNo': regNo,
        'date': dateKey,
        'logoutTime': FieldValue.serverTimestamp(),
        'logoutType': 'normal',
      }, SetOptions(merge: true));

      debugPrint('[Attendance] Normal logout recorded: $docId');

      // Notify all admins about normal logout.
      unawaited(_notifyAdmins(
        title: '✅ Student Logged Out',
        body:  '$studentName ($regNo) has logged out successfully.',
        data:  {
          'type':        'student_logout',
          'studentName': studentName,
          'regNo':       regNo,
        },
      ));

      return LogoutResult(
        allowed:       true,
        reason:        'Logout successful.',
        currentPeriod: lastPeriod.id,
      );
    } catch (e, st) {
      debugPrint('[Attendance] handleLogout error: $e\n$st');
      rethrow;
    }
  }

  // ── Internal: notify all admins via backend ────────────────────────────────

  Future<void> _notifyAdmins({
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    const backendUrl =
        'https://smartclassroommontoring-system.onrender.com/notify-admins';
    const maxAttempts = 2;
    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final response = await http.post(
            Uri.parse(backendUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'title': title,
              'body': body,
              'data': data,
            }),
          ).timeout(const Duration(seconds: 65));
          if (response.statusCode == 200) {
            debugPrint('[Attendance] notifyAdmins success via $backendUrl (attempt $attempt)');
            return;
          } else {
            debugPrint('[Attendance] notifyAdmins HTTP ${response.statusCode} attempt $attempt via $backendUrl');
          }
        } catch (e) {
          debugPrint('[Attendance] notifyAdmins attempt $attempt failed via $backendUrl: $e');
        }
      }

      debugPrint('[Attendance] notifyAdmins failed after all attempts');
    } catch (e) {
      debugPrint('[Attendance] _notifyAdmins error: $e');
    }
  }

  // ── Internal: fetch period docs ───────────────────────────────────────────

  Future<List<_PeriodInfo>> _fetchPeriods(
      String classId, String dayName, String lowerDay) async {
    // Try title-case day, then lowercase (mirrors TimetableMonitor behaviour)
    var snap = await _db
        .collection('timetables')
        .doc(classId)
        .collection(dayName)
        .get();

    if (snap.docs.isEmpty && dayName != lowerDay) {
      snap = await _db
          .collection('timetables')
          .doc(classId)
          .collection(lowerDay)
          .get();
    }

    return snap.docs.map((doc) {
      final data      = doc.data();
      final startTime = (data['startTime'] as num?)?.toInt() ?? 0;
      final endTime   = (data['endTime']   as num?)?.toInt() ?? 0;
      return _PeriodInfo(id: doc.id, startTime: startTime, endTime: endTime);
    }).toList();
  }
}

// ── Internal model ────────────────────────────────────────────────────────────

class _PeriodInfo {
  final String id;
  final int startTime; // minutes from midnight
  final int endTime;   // minutes from midnight
  const _PeriodInfo({
    required this.id,
    required this.startTime,
    required this.endTime,
  });
}

// ── Public result model ───────────────────────────────────────────────────────

/// The outcome of a [AttendanceService.handleLogout] call.
class LogoutResult {
  /// `true`  → logout is permitted; caller should sign the user out.
  /// `false` → logout is blocked; show [reason] to the student.
  final bool allowed;

  /// Human-readable message to display in a snackbar / dialog.
  final String reason;

  /// The Firestore doc ID of the period active at logout time (or attempted).
  final String currentPeriod;

  const LogoutResult({
    required this.allowed,
    required this.reason,
    required this.currentPeriod,
  });
}
