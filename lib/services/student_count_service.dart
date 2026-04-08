import 'package:cloud_firestore/cloud_firestore.dart';

/// A service to manage real-time student count from the ML camera detector.
///
/// This service provides a stream to listen for live updates of the student
/// count from the `classroom_metrics` collection in Firestore.
class StudentCountService {
  static final StudentCountService _instance = StudentCountService._internal();
  factory StudentCountService() => _instance;
  StudentCountService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Streams the real-time student count for a given classroom.
  ///
  /// Listens to the specific document in the `classroom_metrics` collection
  /// and yields the `studentCount` value whenever it changes.
  ///
  /// [classroomId] The unique identifier for the classroom to monitor.
  ///
  /// Returns a [Stream<int>] that emits the latest student count.
  /// If the document doesn't exist or has no count, it returns 0.
  Stream<int> streamStudentCount({required String classroomId}) {
    return _db
        .collection('classroom_metrics')
        .doc(classroomId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return 0;
      }
      // Safely cast the studentCount to an integer, defaulting to 0.
      return (snapshot.data()!['studentCount'] as num?)?.toInt() ?? 0;
    });
  }
}
