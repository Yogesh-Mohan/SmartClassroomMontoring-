import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'dart:io';
import '../models/task_model.dart';

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
  final FirebaseFirestore _firestore;
  final fs.FirebaseStorage _storage;

  TasksService({FirebaseFirestore? firestore, fs.FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? fs.FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection('tasks');

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
  }) {
    final classes = normalizeClassCandidates(classCandidates);
    return _tasksCollection.orderBy('dueDate').snapshots().asyncMap((snapshot) async {
      final allTasks = snapshot.docs
          .map((doc) => Task.fromFirestore(doc))
          .where((task) => task.isActive)
          .where((task) {
            final classMatch = classes.contains(task.targetClassId);
            if (!classMatch) return false;
            if (task.audienceType == TaskAudienceType.allInClass) return true;
            return task.assigneeUIDs.contains(studentUID);
          })
          .toList();

      final out = <TaskWithSubmission>[];
      for (final task in allTasks) {
        final subSnap = await _tasksCollection
            .doc(task.id)
            .collection('submissions')
            .doc(studentUID)
            .get();

        TaskSubmission? submission;
        if (subSnap.exists) {
          submission = TaskSubmission.fromMap(subSnap.data()!);
        }
        out.add(TaskWithSubmission(task: task, submission: submission));
      }
      return out;
    });
  }

  Stream<Map<String, int>> streamTaskStats({
    required String studentUID,
    required List<String> classCandidates,
  }) {
    return streamStudentAssignedTasks(
      studentUID: studentUID,
      classCandidates: classCandidates,
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
      assigneeUIDs: audienceType == TaskAudienceType.selectedStudents
          ? assigneeUIDs
          : const [],
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
    final path = 'task_proofs/$taskId/$studentUID/attempt_$nextAttempt.jpg';
    final uploadTask = await _storage.ref(path).putFile(imageFile);
    final url = await uploadTask.ref.getDownloadURL();

    await submissionRef.set({
      'studentUID': studentUID,
      'proofImageUrl': url,
      'proofStoragePath': path,
      'reviewStatus': 'pending',
      'attemptCount': nextAttempt,
      'submittedAt': FieldValue.serverTimestamp(),
      'reviewedByUID': '',
      'reviewedAt': null,
      'reviewComment': '',
      'taskId': taskId,
    }, SetOptions(merge: true));
  }

  Stream<List<PendingSubmissionItem>> streamPendingSubmissions() {
    return _firestore
        .collectionGroup('submissions')
        .where('reviewStatus', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
      final out = <PendingSubmissionItem>[];
      for (final doc in snapshot.docs) {
        final taskRef = doc.reference.parent.parent;
        if (taskRef == null) continue;
        final taskSnap = await taskRef.get();
        if (!taskSnap.exists) continue;
        final task = Task.fromFirestore(taskSnap);
        final submission = TaskSubmission.fromMap(doc.data());
        out.add(PendingSubmissionItem(
          taskId: taskRef.id,
          task: task,
          submission: submission,
        ));
      }
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
          return values.contains(classId);
        })
        .toList();
  }

  Future<List<String>> getAvailableClassIdsFromTimetable() async {
    final snap = await _firestore.collection('timetables').get();
    return snap.docs.map((e) => e.id).toList();
  }
}
