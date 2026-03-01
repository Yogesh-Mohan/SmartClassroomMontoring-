import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student_alert_model.dart';

class StudentAlertsService {
  final FirebaseFirestore _firestore;

  StudentAlertsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _alertsCollection =>
      _firestore.collection('student_alerts');

  Stream<List<StudentAlert>> streamStudentAlerts({
    required List<String> studentLookupKeys,
    int limit = 50,
  }) {
    final keys = _normalizeKeys(studentLookupKeys);
    if (keys.isEmpty) {
      return Stream.value(const <StudentAlert>[]);
    }

    final queryKeys = keys.take(10).toList();
    return _alertsCollection
        .where('recipientKeys', arrayContainsAny: queryKeys)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(StudentAlert.fromFirestore).toList());
  }

  Future<void> markAlertRead(String alertId) {
    return _alertsCollection.doc(alertId).set(
      {'isRead': true},
      SetOptions(merge: true),
    );
  }

  Future<void> createTaskAlert({
    required String taskId,
    required String taskTitle,
    required List<String> recipientKeys,
    String? cycleKey,
  }) async {
    final keys = _normalizeKeys(recipientKeys);
    if (keys.isEmpty) return;

    await _alertsCollection.add({
      'type': 'task_assigned',
      'title': 'Task Alert (Admin)',
      'message': '"$taskTitle" task assigned by admin. Tap to open Tasks.',
      'taskId': taskId,
      'recipientKeys': keys,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'cycleKey': cycleKey ?? '',
    });
  }

  List<String> _normalizeKeys(List<String> keys) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final value in keys) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        normalized.add(trimmed);
      }
    }
    return normalized;
  }
}