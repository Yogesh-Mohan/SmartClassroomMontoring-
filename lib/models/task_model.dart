import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskAudienceType { allInClass, selectedStudents }
enum TaskSubmissionStatus { notSubmitted, pending, accepted, rejected }

/// Model class representing an admin-assigned task
class Task {
  final String? id;
  final String title;
  final String description;
  final String createdByUID;
  final String targetClassId;
  final TaskAudienceType audienceType;
  final List<String> assigneeUIDs;
  final DateTime dueDate;
  final DateTime createdAt;
  final bool isActive;

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.createdByUID,
    required this.targetClassId,
    required this.audienceType,
    required this.assigneeUIDs,
    required this.dueDate,
    DateTime? createdAt,
    this.isActive = true,
  }) : createdAt = createdAt ?? DateTime.now();

  static TaskAudienceType _audienceFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'selected':
      case 'selectedstudents':
        return TaskAudienceType.selectedStudents;
      default:
        return TaskAudienceType.allInClass;
    }
  }

  static String _audienceToString(TaskAudienceType type) {
    switch (type) {
      case TaskAudienceType.selectedStudents:
        return 'selected';
      case TaskAudienceType.allInClass:
        return 'all';
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

  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      createdByUID: data['createdByUID'] as String? ?? '',
      targetClassId: data['targetClassId'] as String? ?? '',
      audienceType: _audienceFromString(data['audienceType'] as String?),
      assigneeUIDs: (data['assigneeUIDs'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      dueDate: _parseDate(data['dueDate']),
      createdAt: _parseDate(data['createdAt']),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'createdByUID': createdByUID,
      'targetClassId': targetClassId,
      'audienceType': _audienceToString(audienceType),
      'assigneeUIDs': assigneeUIDs,
      'dueDate': Timestamp.fromDate(dueDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
    };
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? createdByUID,
    String? targetClassId,
    TaskAudienceType? audienceType,
    List<String>? assigneeUIDs,
    DateTime? dueDate,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdByUID: createdByUID ?? this.createdByUID,
      targetClassId: targetClassId ?? this.targetClassId,
      audienceType: audienceType ?? this.audienceType,
      assigneeUIDs: assigneeUIDs ?? this.assigneeUIDs,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  bool get isOverdue {
    return DateTime.now().isAfter(dueDate);
  }

  bool get isDueToday {
    final now = DateTime.now();
    return dueDate.year == now.year &&
           dueDate.month == now.month &&
           dueDate.day == now.day;
  }

  @override
  String toString() {
    return 'Task(id: $id, title: $title, class: $targetClassId, dueDate: $dueDate)';
  }
}

class TaskSubmission {
  final String studentUID;
  final String proofImageUrl;
  final String proofStoragePath;
  final TaskSubmissionStatus status;
  final int attemptCount;
  final DateTime submittedAt;
  final String reviewedByUID;
  final DateTime? reviewedAt;
  final String reviewComment;

  const TaskSubmission({
    required this.studentUID,
    required this.proofImageUrl,
    required this.proofStoragePath,
    required this.status,
    required this.attemptCount,
    required this.submittedAt,
    required this.reviewedByUID,
    required this.reviewedAt,
    required this.reviewComment,
  });

  static TaskSubmissionStatus _statusFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pending':
        return TaskSubmissionStatus.pending;
      case 'accepted':
        return TaskSubmissionStatus.accepted;
      case 'rejected':
        return TaskSubmissionStatus.rejected;
      default:
        return TaskSubmissionStatus.notSubmitted;
    }
  }

  static String _statusToString(TaskSubmissionStatus status) {
    switch (status) {
      case TaskSubmissionStatus.pending:
        return 'pending';
      case TaskSubmissionStatus.accepted:
        return 'accepted';
      case TaskSubmissionStatus.rejected:
        return 'rejected';
      case TaskSubmissionStatus.notSubmitted:
        return 'notSubmitted';
    }
  }

  factory TaskSubmission.fromMap(Map<String, dynamic> data) {
    return TaskSubmission(
      studentUID: data['studentUID'] as String? ?? '',
      proofImageUrl: data['proofImageUrl'] as String? ?? '',
      proofStoragePath: data['proofStoragePath'] as String? ?? '',
      status: _statusFromString(data['reviewStatus'] as String?),
      attemptCount: (data['attemptCount'] as num?)?.toInt() ?? 1,
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedByUID: data['reviewedByUID'] as String? ?? '',
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      reviewComment: data['reviewComment'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentUID': studentUID,
      'proofImageUrl': proofImageUrl,
      'proofStoragePath': proofStoragePath,
      'reviewStatus': _statusToString(status),
      'attemptCount': attemptCount,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'reviewedByUID': reviewedByUID,
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewComment': reviewComment,
    };
  }
}
