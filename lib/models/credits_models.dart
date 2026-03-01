import 'package:cloud_firestore/cloud_firestore.dart';

class CreditsDashboardState {
  final double monthlyActivityScore;
  final double semesterActivityScore;
  final double activityBoostPoints;
  final double activityBoostPercent;
  final List<InteractionSubjectScore> interactionSubjects;
  final List<InternalMarkEntry> internalMarks;

  const CreditsDashboardState({
    required this.monthlyActivityScore,
    required this.semesterActivityScore,
    required this.activityBoostPoints,
    required this.activityBoostPercent,
    required this.interactionSubjects,
    required this.internalMarks,
  });

  bool get hasActivity => monthlyActivityScore > 0 || semesterActivityScore > 0;
  bool get hasInteractions => interactionSubjects.isNotEmpty;
  bool get hasInternalMarks => internalMarks.isNotEmpty;
}

class InteractionSubjectScore {
  final String subjectId;
  final String subjectName;
  final double totalScore;
  final List<InteractionScoreEntry> entries;

  const InteractionSubjectScore({
    required this.subjectId,
    required this.subjectName,
    required this.totalScore,
    required this.entries,
  });
}

class InteractionScoreEntry {
  final String id;
  final String topic;
  final double score;
  final String createdBy;
  final DateTime createdAt;

  const InteractionScoreEntry({
    required this.id,
    required this.topic,
    required this.score,
    required this.createdBy,
    required this.createdAt,
  });
}

class InternalMarkEntry {
  final String subjectId;
  final String subjectName;
  final double baseInternal;
  final double activityBoost;
  final double interactionBoost;
  final double finalInternal;

  const InternalMarkEntry({
    required this.subjectId,
    required this.subjectName,
    required this.baseInternal,
    required this.activityBoost,
    required this.interactionBoost,
    required this.finalInternal,
  });
}

class CertificateRequest {
  final String id;
  final String studentId;
  final String studentName;
  final String semester;
  final String title;
  final String fileUrl;
  final String fileType;
  final double fileSizeMb;
  final String status;
  final DateTime submittedAt;
  final String? advisorId;
  final double? advisorScore;
  final String? description;

  CertificateRequest({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.semester,
    required this.title,
    required this.fileUrl,
    required this.fileType,
    required this.fileSizeMb,
    required this.status,
    required this.submittedAt,
    this.advisorId,
    this.advisorScore,
    this.description,
  });

  factory CertificateRequest.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CertificateRequest(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? 'Student').toString(),
      semester: (data['semester'] ?? 'S1').toString(),
      title: (data['title'] ?? 'Certificate').toString(),
      fileUrl: (data['fileUrl'] ?? '').toString(),
      fileType: (data['fileType'] ?? '').toString(),
      fileSizeMb: _asDouble(data['fileSizeMb']),
      status: (data['status'] ?? 'Pending').toString(),
      submittedAt: _parseTimestamp(data['submittedAt']),
      advisorId: data['approvedBy']?.toString(),
      advisorScore: data['advisorScore'] != null ? _asDouble(data['advisorScore']) : null,
      description: data['description']?.toString(),
    );
  }
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
