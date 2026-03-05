import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:async';
import 'package:async/async.dart';
import 'package:firebase_storage/firebase_storage.dart' as fs;
import '../models/task_model.dart';
import 'cloudinary_upload_service.dart';

class TaskWithSubmission {
  final Task task;
  final TaskSubmission? submission;

  const TaskWithSubmission({required this.task, this.submission});

  TaskSubmissionStatus get status =>
      submission?.status ?? TaskSubmissionStatus.notSubmitted;

  bool get isCompleted => status == TaskSubmissionStatus.accepted;
}

class PendingSubmissionItem {
  final String taskId;
  final Task task;
  final TaskSubmission submission;

  const PendingSubmissionItem({
    required this.taskId,
    required this.task,
    required this.submission,
  });
}

/// Service for admin-assigned task workflow
class TasksService {
  static const Duration _completedRetention = Duration(days: 7);

  final FirebaseFirestore _firestore;
  final fs.FirebaseStorage _storage;

  TasksService({FirebaseFirestore? firestore, fs.FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? fs.FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection('tasks');

  bool _isExpiredCompletedSubmission(TaskSubmission? submission) {
    if (submission == null) return false;
    if (submission.status != TaskSubmissionStatus.accepted) return false;
    final anchor = submission.reviewedAt ?? submission.submittedAt;
    return DateTime.now().isAfter(anchor.add(_completedRetention));
  }

  Future<void> _cleanupExpiredAcceptedSubmission({
    required String taskId,
    required String studentUID,
  }) async {
    try {
      await _tasksCollection
          .doc(taskId)
          .collection('submissions')
          .doc(studentUID)
          .delete();
    } catch (_) {}
  }

  String _normalizeClassKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _classAbbreviation(String value) {
    final words = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 2) return '';
    return words.map((w) => w[0]).join();
  }

  int? _extractYear(String value) {
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  ({int start, int end})? _extractBatchRange(String value) {
    final match = RegExp(r'(19|20)\d{2}\D+(19|20)\d{2}').firstMatch(value);
    if (match == null) return null;
    final numbers = RegExp(r'(19|20)\d{2}')
        .allMatches(match.group(0)!)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>()
        .toList();
    if (numbers.length < 2) return null;
    final start = numbers.first;
    final end = numbers.last;
    return (start: start <= end ? start : end, end: start <= end ? end : start);
  }

  bool _classMatches(String taskClassId, List<String> classCandidates) {
    final taskKey = _normalizeClassKey(taskClassId);
    if (taskKey.isEmpty) return false;

    final cleanedCandidates = classCandidates
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (final candidate in classCandidates) {
      final candidateKey = _normalizeClassKey(candidate);
      if (candidateKey == taskKey) {
        return true;
      }
      if (candidateKey.isNotEmpty &&
          (candidateKey.contains(taskKey) || taskKey.contains(candidateKey))) {
        return true;
      }

      final taskAbbr = _classAbbreviation(taskClassId);
      final candidateAbbr = _classAbbreviation(candidate);
      if (taskAbbr.isNotEmpty && candidateAbbr.isNotEmpty && taskAbbr == candidateAbbr) {
        return true;
      }
    }

    final taskYear = _extractYear(taskClassId);
    if (taskYear != null) {
      for (final candidate in cleanedCandidates) {
        final range = _extractBatchRange(candidate);
        if (range == null) continue;
        if (taskYear >= range.start && taskYear <= range.end) {
          return true;
        }
      }
    }

    return false;
  }

  List<String> normalizeClassCandidates(List<String> classes) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in classes) {
      final s = value.trim();
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  Stream<List<TaskWithSubmission>> streamStudentAssignedTasks({
    required String studentUID,
    required List<String> classCandidates,
    List<String> studentLookupKeys = const [],
  }) {
    final effectiveStudentUID = studentUID.trim();
    final classes = normalizeClassCandidates(classCandidates);
    final lookupKeys = <String>{
      if (effectiveStudentUID.isNotEmpty) effectiveStudentUID,
      ...studentLookupKeys.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }.toList();
    final assigneeQueryUid = effectiveStudentUID;

    if (classes.isEmpty && lookupKeys.isEmpty) {
      return Stream.value(const <TaskWithSubmission>[]);
    }

    final taskChangeTriggers = <Stream<void>>[
      _tasksCollection
          .where('audienceType', whereIn: ['all', 'allInClass'])
          .snapshots()
          .map((_) {}),
      Stream<void>.periodic(const Duration(seconds: 8), (_) {}),
    ];

    if (assigneeQueryUid.isNotEmpty) {
      taskChangeTriggers.add(
        _tasksCollection
            .where('assigneeUIDs', arrayContains: assigneeQueryUid)
            .snapshots()
            .map((_) {}),
      );
    }

    return StreamGroup.merge(taskChangeTriggers).asyncMap((_) async {
      final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      final allInClassSnap = await _tasksCollection
          .where('audienceType', whereIn: ['all', 'allInClass'])
          .get();
      for (final doc in allInClassSnap.docs) {
        allDocs[doc.id] = doc;
      }

      if (assigneeQueryUid.isNotEmpty) {
        final selectedSnap = await _tasksCollection
            .where('assigneeUIDs', arrayContains: assigneeQueryUid)
            .get();
        for (final doc in selectedSnap.docs) {
          allDocs[doc.id] = doc;
        }
      }

      final allTasks = allDocs.values
          .map((doc) => Task.fromFirestore(doc))
          .where((task) => task.isActive)
          .where((task) {
            final assignedToCurrentStudent =
                lookupKeys.isNotEmpty &&
                task.assigneeUIDs.any((id) => lookupKeys.contains(id.trim()));

            if (task.audienceType == TaskAudienceType.selectedStudents) {
              return assignedToCurrentStudent;
            }

            if (assignedToCurrentStudent) {
              return true;
            }

            return _classMatches(task.targetClassId, classes);
          })
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      final out = <TaskWithSubmission>[];
      for (final task in allTasks) {
        final taskId = task.id;
        if (taskId == null || taskId.isEmpty) continue;
        TaskSubmission? submission;
        if (effectiveStudentUID.isNotEmpty) {
          try {
            final subSnap = await _tasksCollection
                .doc(taskId)
                .collection('submissions')
                .doc(effectiveStudentUID)
                .get();
            if (subSnap.exists) {
              submission = TaskSubmission.fromMap(subSnap.data()!);
            }
          } catch (_) {
            submission = null;
          }
        }

        if (_isExpiredCompletedSubmission(submission)) {
          if (effectiveStudentUID.isNotEmpty) {
            await _cleanupExpiredAcceptedSubmission(
              taskId: taskId,
              studentUID: effectiveStudentUID,
            );
          }
          continue;
        }

        out.add(TaskWithSubmission(task: task, submission: submission));
      }
      return out;
    });
  }

  Stream<Map<String, int>> streamTaskStats({
    required String studentUID,
    required List<String> classCandidates,
    List<String> studentLookupKeys = const [],
  }) {
    return streamStudentAssignedTasks(
      studentUID: studentUID,
      classCandidates: classCandidates,
      studentLookupKeys: studentLookupKeys,
    ).map((items) {
      final total = items.length;
      final completed = items.where((e) => e.isCompleted).length;
      return {'completed': completed, 'total': total};
    });
  }

  Future<String> createTaskAssignment({
    required String createdByUID,
    required String targetClassId,
    required String title,
    required String description,
    required DateTime dueDate,
    required TaskAudienceType audienceType,
    required List<String> assigneeUIDs,
  }) async {
    final task = Task(
      title: title,
      description: description,
      createdByUID: createdByUID,
      targetClassId: targetClassId,
      audienceType: audienceType,
      assigneeUIDs: assigneeUIDs,
      dueDate: dueDate,
      createdAt: DateTime.now(),
      isActive: true,
    );

    final doc = await _tasksCollection.add(task.toFirestore());
    return doc.id;
  }

  Future<void> submitTaskProof({
    required String taskId,
    required String studentUID,
    required File imageFile,
    int maxAttempts = 3,
  }) async {
    final submissionRef = _tasksCollection
        .doc(taskId)
        .collection('submissions')
        .doc(studentUID);

    final previous = await submissionRef.get();
    final previousAttempt =
        (previous.data()?['attemptCount'] as num?)?.toInt() ?? 0;
    if (previousAttempt >= maxAttempts) {
      throw Exception('Maximum proof attempts reached ($maxAttempts).');
    }

    final nextAttempt = previousAttempt + 1;
    final cloudinaryPath =
        'cloudinary/task_proofs/$taskId/$studentUID/attempt_$nextAttempt.jpg';

    String url;
    String proofPath;
    if (CloudinaryUploadService.isConfigured) {
      url = await CloudinaryUploadService.uploadFile(
        file: imageFile,
        resourceType: 'image',
        folder: 'task_proofs/$taskId/$studentUID',
      );
      proofPath = cloudinaryPath;
    } else {
      final firebasePath = 'task_proofs/$taskId/$studentUID/attempt_$nextAttempt.jpg';
      final uploadTask = await _storage.ref(firebasePath).putFile(imageFile);
      url = await uploadTask.ref.getDownloadURL();
      proofPath = firebasePath;
    }

    await submissionRef.set({
      'studentUID': studentUID,
      'proofImageUrl': url,
      'proofStoragePath': proofPath,
      'reviewStatus': 'pending',
      'attemptCount': nextAttempt,
      'submittedAt': FieldValue.serverTimestamp(),
      'reviewedByUID': '',
      'reviewedAt': null,
      'reviewComment': '',
      'taskId': taskId,
    }, SetOptions(merge: true));
  }

  Stream<List<PendingSubmissionItem>> streamPendingSubmissions({
    required String reviewerUID,
  }) {
    final reviewer = reviewerUID.trim();
    if (reviewer.isEmpty) {
      return Stream.value(const <PendingSubmissionItem>[]);
    }

    return _tasksCollection
        .where('createdByUID', isEqualTo: reviewer)
        .snapshots()
        .asyncMap((tasksSnapshot) async {
      final out = <PendingSubmissionItem>[];
      for (final taskDoc in tasksSnapshot.docs) {
        final task = Task.fromFirestore(taskDoc);
        final pendingSubmissions = await taskDoc.reference
            .collection('submissions')
            .where('reviewStatus', isEqualTo: 'pending')
            .get();

        for (final submissionDoc in pendingSubmissions.docs) {
          final submission = TaskSubmission.fromMap(submissionDoc.data());
          out.add(PendingSubmissionItem(
            taskId: taskDoc.id,
            task: task,
            submission: submission,
          ));
        }
      }

      out.sort((a, b) => b.submission.submittedAt.compareTo(a.submission.submittedAt));
      return out;
    });
  }

  Future<void> reviewSubmission({
    required String taskId,
    required String studentUID,
    required bool accepted,
    required String reviewedByUID,
    String comment = '',
  }) async {
    await _tasksCollection
        .doc(taskId)
        .collection('submissions')
        .doc(studentUID)
        .set({
      'reviewStatus': accepted ? 'accepted' : 'rejected',
      'reviewedByUID': reviewedByUID,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewComment': comment,
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getStudentsForClass(String classId) async {
    final snap = await _firestore.collection('students').get();
    final classKey = _normalizeClassKey(classId);
    return snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((row) {
          final values = [
            row['className'],
            row['class'],
            row['classId'],
            row['section'],
            row['course'],
            row['department'],
            row['batch'],
          ].where((e) => e != null).map((e) => e.toString()).toList();

          if (values.any((v) => _normalizeClassKey(v) == classKey)) {
            return true;
          }

          if (_classMatches(classId, values)) {
            return true;
          }

          return values.any((v) => _classMatches(v, [classId]));
        })
        .toList();
  }

  Future<List<String>> getAvailableClassIdsFromTimetable() async {
    final snap = await _firestore.collection('timetables').get();
    return snap.docs.map((e) => e.id).toList();
  }
}
