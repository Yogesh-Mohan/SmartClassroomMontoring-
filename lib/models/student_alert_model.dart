import 'package:cloud_firestore/cloud_firestore.dart';

enum StudentAlertType { taskAssigned, ruleSummary }

class StudentAlert {
  final String id;
  final StudentAlertType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String? taskId;
  final String? cycleKey;

  const StudentAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.taskId,
    this.cycleKey,
  });

  static StudentAlertType _typeFromRaw(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'rulesummary':
      case 'rule_summary':
      case 'rule':
        return StudentAlertType.ruleSummary;
      default:
        return StudentAlertType.taskAssigned;
    }
  }

  static String _typeToRaw(StudentAlertType type) {
    switch (type) {
      case StudentAlertType.ruleSummary:
        return 'rule_summary';
      case StudentAlertType.taskAssigned:
        return 'task_assigned';
    }
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  factory StudentAlert.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return StudentAlert(
      id: doc.id,
      type: _typeFromRaw(data['type'] as String?),
      title: (data['title'] as String? ?? '').trim(),
      message: (data['message'] as String? ?? '').trim(),
      createdAt: _parseDate(data['createdAt']),
      isRead: data['isRead'] as bool? ?? false,
      taskId: (data['taskId'] as String?)?.trim(),
      cycleKey: (data['cycleKey'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': _typeToRaw(type),
      'title': title,
      'message': message,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
      'taskId': taskId,
      'cycleKey': cycleKey,
    };
  }
}