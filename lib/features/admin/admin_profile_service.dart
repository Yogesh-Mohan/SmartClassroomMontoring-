import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminProfileService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream the admin profile by email — UID-independent.
  static Stream<Map<String, dynamic>> streamProfile(String email) {
    final normalized = email.trim().toLowerCase();
    return _firestore
        .collection('admins')
        .where('gmail', isEqualTo: normalized)
        .limit(1)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
      final snap2 = await _firestore
          .collection('admins')
          .where('email', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap2.docs.isEmpty) return <String, dynamic>{};
      return snap2.docs.first.data();
    });
  }

  /// One-time fetch
  static Future<Map<String, dynamic>> fetchProfile(String email) async {
    try {
      final snap = await _firestore
          .collection('admins')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return {};
      return snap.docs.first.data();
    } catch (e) {
      debugPrint('AdminProfileService.fetchProfile: $e');
      return {};
    }
  }
}
