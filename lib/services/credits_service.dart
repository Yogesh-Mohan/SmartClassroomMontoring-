import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/credits_models.dart';

class CreditsService {
  CreditsService._();
  static final CreditsService instance = CreditsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Stream<CreditsDashboardState> streamStudentDashboard({
    required String studentId,
    String? studentUid,
    required String semester,
  }) {
    final normalizedStudentId = studentId.trim();
    final normalizedStudentUid = (studentUid ?? '').trim();
    final effectiveUid =
        normalizedStudentUid.isNotEmpty ? normalizedStudentUid : normalizedStudentId;

    // Trigger on certificate changes (by studentUid) + periodic refresh.
    // Using asyncMap with individual try-catch prevents a single failing
    // Firestore query (e.g. security rule denial) from crashing the whole stream.
    final triggers = StreamGroup.merge([
      _db
          .collection('certificates')
          .where('studentUid', isEqualTo: effectiveUid)
          .snapshots()
          .map((_) {}),
      Stream<void>.periodic(const Duration(seconds: 10), (_) {}),
    ]);

    return triggers.asyncMap((_) async {
      // ── Certificates ─────────────────────────────────────────────────────
      final certDocMap = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      try {
        final snap = await _db
            .collection('certificates')
            .where('studentUid', isEqualTo: effectiveUid)
            .get();
        for (final doc in snap.docs) { certDocMap[doc.id] = doc; }
      } catch (_) {}
      if (normalizedStudentId.isNotEmpty && normalizedStudentId != effectiveUid) {
        try {
          final snap = await _db
              .collection('certificates')
              .where('studentId', isEqualTo: normalizedStudentId)
              .get();
          for (final doc in snap.docs) { certDocMap.putIfAbsent(doc.id, () => doc); }
        } catch (_) {}
      }
      final certDocs = certDocMap.values.toList();

      // ── Interaction scores ────────────────────────────────────────────────
      final interactionDocMap =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      try {
        final snap = await _db
            .collection('interactionScores')
            .where('studentId', isEqualTo: normalizedStudentId)
            .where('semester', isEqualTo: semester)
            .get();
        for (final doc in snap.docs) { interactionDocMap[doc.id] = doc; }
      } catch (_) {}
      if (normalizedStudentUid.isNotEmpty) {
        try {
          final snap = await _db
              .collection('interactionScores')
              .where('studentUid', isEqualTo: normalizedStudentUid)
              .where('semester', isEqualTo: semester)
              .get();
          for (final doc in snap.docs) { interactionDocMap.putIfAbsent(doc.id, () => doc); }
        } catch (_) {}
      }
      final interactionDocs = interactionDocMap.values.toList();

      // ── Internal marks ────────────────────────────────────────────────────
      final marksDocMap =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      try {
        final snap = await _db
            .collection('internalMarks')
            .where('studentId', isEqualTo: normalizedStudentId)
            .where('semester', isEqualTo: semester)
            .get();
        for (final doc in snap.docs) { marksDocMap[doc.id] = doc; }
      } catch (_) {}
      if (normalizedStudentUid.isNotEmpty) {
        try {
          final snap = await _db
              .collection('internalMarks')
              .where('studentUid', isEqualTo: normalizedStudentUid)
              .where('semester', isEqualTo: semester)
              .get();
          for (final doc in snap.docs) { marksDocMap.putIfAbsent(doc.id, () => doc); }
        } catch (_) {}
      }
      final marksDocs = marksDocMap.values.toList();

      // ── Compute dashboard state ───────────────────────────────────────────
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      double monthlyActivity = 0;
      double semesterActivity = 0;

      for (final doc in certDocs) {
        if ((doc.data()['status'] ?? '') != 'Approved') continue;
        final score = _asDouble(doc.data()['advisorScore']);
        final approvedAt = _parseTimestamp(doc.data()['approvedAt']);
        if (!approvedAt.isBefore(startOfMonth) && approvedAt.isBefore(nextMonth)) {
          monthlyActivity += score;
        }
        if ((doc.data()['semester'] ?? semester).toString() == semester) {
          semesterActivity += score;
        }
      }

      final activityBoostPoints = ((semesterActivity).clamp(0, 10) / 10) * 2;
      final activityBoostPercent = (activityBoostPoints / 2) * 100;

      final Map<String, List<InteractionScoreEntry>> entriesBySubject = {};
      final Map<String, double> totalsBySubject = {};
      final Map<String, String> subjectNameById = {};

      for (final doc in interactionDocs) {
        final data = doc.data();
        final subjectId = (data['subjectId'] ?? 'subject').toString();
        final subjectName = (data['subjectName'] ?? 'Subject').toString();
        final entry = InteractionScoreEntry(
          id: doc.id,
          topic: (data['topic'] ?? data['topicName'] ?? 'Topic').toString(),
          score: _asDouble(data['score']),
          createdBy: (data['createdBy'] ?? 'Teacher').toString(),
          createdAt: _parseTimestamp(data['createdAt']),
        );
        entriesBySubject.putIfAbsent(subjectId, () => []).add(entry);
        totalsBySubject[subjectId] = (totalsBySubject[subjectId] ?? 0) + entry.score;
        subjectNameById[subjectId] = subjectName;
      }

      final interactions = entriesBySubject.entries.map((entry) {
        final list = [...entry.value]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return InteractionSubjectScore(
          subjectId: entry.key,
          subjectName: subjectNameById[entry.key] ?? 'Subject',
          totalScore: totalsBySubject[entry.key] ?? 0,
          entries: list,
        );
      }).toList()
        ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

      final internals = marksDocs.map((doc) {
        final data = doc.data();
        return InternalMarkEntry(
          subjectId: (data['subjectId'] ?? doc.id).toString(),
          subjectName: (data['subjectName'] ?? 'Subject').toString(),
          baseInternal: _asDouble(data['baseInternal']),
          activityBoost: _asDouble(data['activityBoost']),
          interactionBoost: _asDouble(data['interactionBoost']),
          finalInternal: _asDouble(data['finalInternal']),
        );
      }).toList()
        ..sort((a, b) => a.subjectName.compareTo(b.subjectName));

      return CreditsDashboardState(
        monthlyActivityScore: double.parse(monthlyActivity.toStringAsFixed(2)),
        semesterActivityScore: double.parse(semesterActivity.toStringAsFixed(2)),
        activityBoostPoints: double.parse(activityBoostPoints.toStringAsFixed(2)),
        activityBoostPercent: double.parse(activityBoostPercent.toStringAsFixed(1)),
        interactionSubjects: interactions,
        internalMarks: internals,
      );
    });
  }

  Future<String> createCertificateRecord({
    required String studentId,
    required String studentUid,
    required String studentName,
    required String semester,
    required String title,
    required String fileUrl,
    required String fileType,
    required double fileSizeMb,
    String? description,
  }) async {
    final doc = await _db.collection('certificates').add({
      'studentId': studentId,
      'studentUid': studentUid,
      'studentName': studentName,
      'semester': semester,
      'title': title,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'fileSizeMb': fileSizeMb,
      'status': 'Pending',
      'description': description,
      'submittedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  UploadTask uploadCertificateFile({
    required String studentId,
    required String semester,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) {
    final ref = _storage
        .ref()
        .child('certificates/$studentId/$semester/$fileName');
    return ref.putData(bytes, SettableMetadata(contentType: contentType));
  }

  Stream<List<CertificateRequest>> streamPendingCertificates() {
    return _db
        .collection('certificates')
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => CertificateRequest.fromSnapshot(doc))
              .toList();
          items.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
          return items;
        });
  }

  Future<void> approveCertificate({
    required String certificateId,
    required String advisorId,
    required String advisorName,
    required double score,
  }) async {
    if (score < 0 || score > 10) {
      throw CreditsException('Score must be between 0 and 10.');
    }

    final certRef = _db.collection('certificates').doc(certificateId);
    final snap = await certRef.get();
    if (!snap.exists) throw CreditsException('Certificate not found.');
    final data = snap.data()!;
    if ((data['status'] ?? 'Pending') != 'Pending') {
      throw CreditsException('Certificate already processed.');
    }

    final studentId = (data['studentId'] ?? '').toString();
    final semester = (data['semester'] ?? 'S1').toString();
    final now = DateTime.now();
    final monthWindow = _MonthWindow(now);

    final monthlyScore = await _sumApprovedCertificates(
      studentId: studentId,
      start: monthWindow.start,
      end: monthWindow.end,
    );
    final availableThisMonth = (10 - monthlyScore).clamp(0, 10).toDouble();
    final awardedScore = min(score, availableThisMonth);
    final isCapped = awardedScore < score;

    final semesterScore = await _sumApprovedCertificates(
      studentId: studentId,
      semester: semester,
    );

    await certRef.update({
      'status': 'Approved',
      'advisorScore': awardedScore,
      'requestedAdvisorScore': score,
      'scoreWasCapped': isCapped,
      'monthlyAvailableAtReview': availableThisMonth,
      'approvedBy': advisorId,
      'approvedByName': advisorName,
      'approvedAt': FieldValue.serverTimestamp(),
    });

    final newSemesterScore = semesterScore + awardedScore;
    final activityBoost = ((newSemesterScore).clamp(0, 10) / 10) * 2;
    final activityPercent = (activityBoost / 2) * 100;

    final studentUid = (data['studentUid'] ?? '').toString().trim();
    final studentDocId = await _resolveStudentDocId(
      studentId: studentId,
      studentUid: studentUid,
    );

    await _db.collection('students').doc(studentDocId).set({
      'credits': {
        'monthlyScore': double.parse((monthlyScore + awardedScore).toStringAsFixed(2)),
        'semesterScore': double.parse(newSemesterScore.toStringAsFixed(2)),
        'activityBoostPoints': double.parse(activityBoost.toStringAsFixed(2)),
        'activityBoostPercent': double.parse(activityPercent.toStringAsFixed(1)),
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    await _updateAllInternalMarks(
      studentId: studentId,
      studentUid: studentUid,
      activityBoost: activityBoost,
    );
  }

  Future<String> _resolveStudentDocId({
    required String studentId,
    required String studentUid,
  }) async {
    final normalizedStudentId = studentId.trim();
    final normalizedStudentUid = studentUid.trim();

    if (normalizedStudentUid.isNotEmpty) {
      final byUidDoc = await _db.collection('students').doc(normalizedStudentUid).get();
      if (byUidDoc.exists) return byUidDoc.id;

      final byUidField = await _db
          .collection('students')
          .where('uid', isEqualTo: normalizedStudentUid)
          .limit(1)
          .get();
      if (byUidField.docs.isNotEmpty) return byUidField.docs.first.id;
    }

    final byStudentId = await _db
        .collection('students')
        .where('studentId', isEqualTo: normalizedStudentId)
        .limit(1)
        .get();
    if (byStudentId.docs.isNotEmpty) return byStudentId.docs.first.id;

    final byRegNo = await _db
        .collection('students')
        .where('regNo', isEqualTo: normalizedStudentId)
        .limit(1)
        .get();
    if (byRegNo.docs.isNotEmpty) return byRegNo.docs.first.id;

    return normalizedStudentUid.isNotEmpty ? normalizedStudentUid : normalizedStudentId;
  }

  Future<void> rejectCertificate({
    required String certificateId,
    required String advisorId,
    String? reason,
  }) async {
    final certRef = _db.collection('certificates').doc(certificateId);
    final snap = await certRef.get();
    if (!snap.exists) throw CreditsException('Certificate not found.');
    if ((snap.data()!['status'] ?? 'Pending') != 'Pending') {
      throw CreditsException('Certificate already processed.');
    }
    await certRef.update({
      'status': 'Rejected',
      'rejectedBy': advisorId,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectionReason': reason,
    });
  }

  Future<void> addInteractionScore({
    required String teacherId,
    required String teacherName,
    required String studentId,
    required String studentName,
    required String subjectId,
    required String subjectName,
    required String semester,
    required String topic,
    required double score,
    String studentUid = '',
  }) async {
    if (score <= 0 || score > 10) {
      throw CreditsException('Interaction score must be between 0 and 10.');
    }

    await _ensureTeacherRole(teacherId);

    final subjectScore = await _sumInteractionScores(
      studentId: studentId,
      subjectId: subjectId,
      semester: semester,
    );
    if (subjectScore + score > 10) {
      throw CreditsException(
        'Subject interaction cap reached. Available: ${(10 - subjectScore).clamp(0, 10).toStringAsFixed(1)}',
      );
    }

    await _db.collection('interactionScores').add({
      'studentId': studentId,
      'studentUid': studentUid.trim(),
      'subjectId': subjectId,
      'subjectName': subjectName,
      'semester': semester,
      'topicName': topic,
      'topic': topic,
      'teacherId': teacherId,
      'score': score,
      'studentName': studentName,
      'createdBy': teacherName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final newSubjectScore = subjectScore + score;
    final interactionBoost = ((newSubjectScore).clamp(0, 10) / 10) * 3;

    final markDocId = '${studentId}_$subjectId';
    final markRef = _db.collection('internalMarks').doc(markDocId);
    final markSnap = await markRef.get();
    final baseInternal = _asDouble(markSnap.data()?['baseInternal']);
    final activityBoost = _asDouble(markSnap.data()?['activityBoost'] ??
        await _getCurrentActivityBoost(studentId));
    final finalInternal = _calculateFinalInternal(
      baseInternal: baseInternal,
      activityBoost: activityBoost,
      interactionBoost: interactionBoost,
    );

    await markRef.set({
      'studentId': studentId,
      if (studentUid.trim().isNotEmpty) 'studentUid': studentUid.trim(),
      'studentName': studentName,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'semester': semester,
      'baseInternal': baseInternal,
      'activityBoost': activityBoost,
      'interactionBoost': interactionBoost,
      'finalInternal': finalInternal,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<InteractionDashboardItem>> streamInteractionDashboard({
    required String studentId,
    required String semester,
  }) {
    final interactionStream = _db
        .collection('interactionScores')
        .where('studentId', isEqualTo: studentId)
        .where('semester', isEqualTo: semester)
        .snapshots();

    final marksStream = _db
        .collection('internalMarks')
        .where('studentId', isEqualTo: studentId)
        .where('semester', isEqualTo: semester)
        .snapshots();

    return StreamZip<QuerySnapshot<Map<String, dynamic>>>([
      interactionStream,
      marksStream,
    ]).map((events) {
      final interactions = events[0];
      final marks = events[1];

      final totalsBySubject = <String, double>{};
      final subjectNames = <String, String>{};

      for (final doc in interactions.docs) {
        final data = doc.data();
        final subjectId = (data['subjectId'] ?? '').toString();
        if (subjectId.isEmpty) continue;
        final score = _asDouble(data['score']);
        totalsBySubject[subjectId] = (totalsBySubject[subjectId] ?? 0) + score;
        subjectNames[subjectId] = (data['subjectName'] ?? 'Subject').toString();
      }

      final marksBySubject = <String, Map<String, dynamic>>{};
      for (final doc in marks.docs) {
        final data = doc.data();
        final subjectId = (data['subjectId'] ?? '').toString();
        if (subjectId.isEmpty) continue;
        marksBySubject[subjectId] = data;
        subjectNames[subjectId] = (data['subjectName'] ?? subjectNames[subjectId] ?? 'Subject').toString();
      }

      final subjectIds = <String>{
        ...totalsBySubject.keys,
        ...marksBySubject.keys,
      };

      final out = <InteractionDashboardItem>[];
      for (final subjectId in subjectIds) {
        final totalScore = double.parse((totalsBySubject[subjectId] ?? 0).toStringAsFixed(2));
        final interactionBoost = double.parse(((totalScore.clamp(0, 10) / 10) * 3).toStringAsFixed(2));
        final interactionBoostPercent = double.parse(((totalScore.clamp(0, 10) / 10) * 100).toStringAsFixed(1));
        final markData = marksBySubject[subjectId];
        final updatedSubjectInternal = _asDouble(markData?['finalInternal']);

        out.add(
          InteractionDashboardItem(
            subjectId: subjectId,
            subjectName: subjectNames[subjectId] ?? 'Subject',
            subjectTotalScore: totalScore,
            interactionBoost: interactionBoost,
            interactionBoostPercent: interactionBoostPercent,
            updatedSubjectInternal: updatedSubjectInternal,
          ),
        );
      }

      out.sort((a, b) => a.subjectName.compareTo(b.subjectName));
      return out;
    });
  }

  Future<void> _updateAllInternalMarks({
    required String studentId,
    required double activityBoost,
    String studentUid = '',
  }) async {
    final marksSnap = await _db
        .collection('internalMarks')
        .where('studentId', isEqualTo: studentId)
        .get();
    if (marksSnap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in marksSnap.docs) {
      final data = doc.data();
      final baseInternal = _asDouble(data['baseInternal']);
      final interactionBoost = _asDouble(data['interactionBoost']);
      final finalInternal = _calculateFinalInternal(
        baseInternal: baseInternal,
        activityBoost: activityBoost,
        interactionBoost: interactionBoost,
      );
      final update = <String, dynamic>{
        'activityBoost': activityBoost,
        'finalInternal': finalInternal,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (studentUid.trim().isNotEmpty) update['studentUid'] = studentUid.trim();
      batch.set(doc.reference, update, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<double> _getCurrentActivityBoost(String studentId) async {
    final studentSnap = await _db.collection('students').doc(studentId).get();
    final activity = studentSnap.data()?['credits']?['activityBoostPoints'];
    return _asDouble(activity);
  }

  Future<double> _sumApprovedCertificates({
    required String studentId,
    DateTime? start,
    DateTime? end,
    String? semester,
  }) async {
    final snap = await _db
        .collection('certificates')
        .where('studentId', isEqualTo: studentId)
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if ((data['status'] ?? '').toString() != 'Approved') continue;
      if (semester != null && (data['semester'] ?? '').toString() != semester) {
        continue;
      }
      if (start != null && end != null) {
        final approvedAt = _parseTimestamp(data['approvedAt']);
        if (approvedAt.isBefore(start) || !approvedAt.isBefore(end)) continue;
      }
      total += _asDouble(data['advisorScore']);
    }
    return total;
  }

  Future<double> _sumInteractionScores({
    required String studentId,
    required String subjectId,
    required String semester,
  }) async {
    final snap = await _db
        .collection('interactionScores')
        .where('studentId', isEqualTo: studentId)
        .where('subjectId', isEqualTo: subjectId)
        .where('semester', isEqualTo: semester)
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      total += _asDouble(doc.data()['score']);
    }
    return total;
  }

  Future<void> _ensureTeacherRole(String teacherId) async {
    if (teacherId.trim().isEmpty) {
      throw CreditsException('Only teacher can add interaction score.');
    }

    final userDoc = await _db.collection('users').doc(teacherId).get();
    final role = (userDoc.data()?['role'] ?? '').toString().toLowerCase().trim();
    if (role == 'teacher') return;

    final teacherDoc = await _db.collection('teachers').doc(teacherId).get();
    if (teacherDoc.exists) return;

    throw CreditsException('Only teacher can add interaction score.');
  }

  double _calculateFinalInternal({
    required double baseInternal,
    required double activityBoost,
    required double interactionBoost,
  }) {
    final total = baseInternal + activityBoost + interactionBoost;
    return double.parse(min(100, total).toStringAsFixed(2));
  }
}

class CreditsException implements Exception {
  final String message;
  CreditsException(this.message);
  @override
  String toString() => message;
}

class InteractionDashboardItem {
  final String subjectId;
  final String subjectName;
  final double subjectTotalScore;
  final double interactionBoost;
  final double interactionBoostPercent;
  final double updatedSubjectInternal;

  const InteractionDashboardItem({
    required this.subjectId,
    required this.subjectName,
    required this.subjectTotalScore,
    required this.interactionBoost,
    required this.interactionBoostPercent,
    required this.updatedSubjectInternal,
  });
}

class _MonthWindow {
  final DateTime start;
  final DateTime end;
  _MonthWindow(DateTime now)
      : start = DateTime(now.year, now.month, 1),
        end = DateTime(now.year, now.month + 1, 1);
}

double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

DateTime _parseTimestamp(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return DateTime.now();
}
