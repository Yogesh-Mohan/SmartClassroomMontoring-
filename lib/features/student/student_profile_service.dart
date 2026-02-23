import 'package:cloud_firestore/cloud_firestore.dart';

class StudentProfileService {
  final _db = FirebaseFirestore.instance;

  // Queries by 'gmail' first (primary Firestore field), falls back to 'email'
  Stream<Map<String, dynamic>?> streamProfile(String email) {
    final normalized = email.trim().toLowerCase();
    return _db
        .collection('students')
        .where('gmail', isEqualTo: normalized)
        .limit(1)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
      final snap2 = await _db
          .collection('students')
          .where('email', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap2.docs.isEmpty) return null;
      return snap2.docs.first.data();
    });
  }
}

