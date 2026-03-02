import 'dart:async';
import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_helpers.dart';

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

  const AdminAlertRow({
    required this.name,
    required this.regNo,
    required this.period,
    required this.timestamp,
  });
}

class AdminDashboardService {
  final FirebaseFirestore _db;

  AdminDashboardService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  DateTime get _periodStart => DateHelpers.getCurrentPeriodStart();
  DateTime get _periodEnd => DateHelpers.getCurrentPeriodEnd();

  Query<Map<String, dynamic>> _todayAttendanceQuery() {
    return _db
        .collection('attendance')
        .where('loginTime', isGreaterThanOrEqualTo: Timestamp.fromDate(_periodStart))
        .where('loginTime', isLessThan: Timestamp.fromDate(_periodEnd));
  }

  Query<Map<String, dynamic>> _todayViolationsQuery() {
    return _db
        .collection('violations')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_periodStart))
        .where('timestamp', isLessThan: Timestamp.fromDate(_periodEnd));
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

  Stream<List<Map<String, dynamic>>> _streamTodayAttendanceDocs() {
    return _todayAttendanceQuery().snapshots().map(
          (snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList(),
        );
  }

  Stream<List<AdminStudentRow>> streamPresentTodayList() {
    return _streamTodayAttendanceDocs().map((rows) {
      final present = rows
          .where((row) => row['logoutTime'] == null)
          .map((row) {
            final uid = (row['studentUID'] ?? '').toString().trim();
            return AdminStudentRow(
              uid: uid,
              name: _displayName(row),
              regNo: _displayRegNo(row),
              classLabel: (row['className'] ?? row['class'] ?? '-').toString(),
            );
          })
          .where((row) => row.uid.isNotEmpty)
          .toList();

      final unique = <String, AdminStudentRow>{};
      for (final row in present) {
        unique[row.uid] = row;
      }

      final out = unique.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    });
  }

  Stream<List<AdminStudentRow>> streamNotLoggedInTodayList() {
    final studentTrigger = _db.collection('students').snapshots().map((_) {});
    final attendanceTrigger = _todayAttendanceQuery().snapshots().map((_) {});

    return StreamGroup.merge([studentTrigger, attendanceTrigger]).asyncMap((_) async {
      final studentsSnap = await _db.collection('students').get();
      final attendanceSnap = await _todayAttendanceQuery().get();

      final loggedUids = <String>{};
      for (final doc in attendanceSnap.docs) {
        final uid = (doc.data()['studentUID'] ?? '').toString().trim();
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
    return _todayViolationsQuery().snapshots().map((snap) {
      final out = snap.docs.map((doc) {
        final data = doc.data();
        final ts = data['timestamp'];
        final time = ts is Timestamp ? ts.toDate() : DateTime.now();
        return AdminAlertRow(
          name: _displayName(data),
          regNo: _displayRegNo(data),
          period: (data['period'] ?? 'Unknown').toString(),
          timestamp: time,
        );
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return out;
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