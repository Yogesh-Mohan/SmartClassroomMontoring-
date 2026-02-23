import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminProfileService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream admin profile — tries 'gmail' field first, falls back to 'email'.
  static Stream<Map<String, dynamic>> streamProfile(String email) {
    final normalized = email.trim().toLowerCase();
    return _db
        .collection('admins')
        .where('gmail', isEqualTo: normalized)
        .limit(1)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
      final snap2 = await _db
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
      final normalized = email.trim().toLowerCase();
      var snap = await _db
          .collection('admins')
          .where('gmail', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
      snap = await _db
          .collection('admins')
          .where('email', isEqualTo: normalized)
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