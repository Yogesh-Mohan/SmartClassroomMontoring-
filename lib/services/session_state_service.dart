import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Persists student login state in Firestore so session state survives app reloads.
///
/// `student_sessions/{uid}`
///   - loginState: 1 (logged in) / 0 (logged out)
///   - lastSeenAt: heartbeat timestamp
///   - explicitLogoutAt: set only on explicit logout
class SessionStateService {
  SessionStateService._();
  static final SessionStateService instance = SessionStateService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>>? _sessionDoc() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return null;
    return _db.collection('student_sessions').doc(uid.trim());
  }

  Future<void> markLoggedIn({
    Map<String, dynamic>? studentData,
    String source = 'login',
  }) async {
    final doc = _sessionDoc();
    final user = _auth.currentUser;
    if (doc == null || user == null) return;

    await doc.set({
      'uid': user.uid,
      'email': (user.email ?? '').trim().toLowerCase(),
      'studentName':
          (studentData?['name'] ?? studentData?['studentName'] ?? '').toString(),
      'regNo':
          (studentData?['regNo'] ?? studentData?['registrationNumber'] ?? '')
              .toString(),
      'loginState': 1,
      'status': 'online',
      'source': source,
      'lastLoginAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'explicitLogoutAt': FieldValue.delete(),
      'logoutReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markHeartbeat({String source = 'heartbeat'}) async {
    final doc = _sessionDoc();
    if (doc == null) return;

    await doc.set({
      'loginState': 1,
      'status': 'online',
      'source': source,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'explicitLogoutAt': FieldValue.delete(),
      'logoutReason': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> markLoggedOut({String reason = 'explicit_logout'}) async {
    final doc = _sessionDoc();
    if (doc == null) return;

    await doc.set({
      'loginState': 0,
      'status': 'offline',
      'logoutReason': reason,
      'explicitLogoutAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markLoggedOutByUid(
    String uid, {
    String reason = 'forced_logout',
  }) async {
    final normalized = uid.trim();
    if (normalized.isEmpty) return;

    await _db.collection('student_sessions').doc(normalized).set({
      'uid': normalized,
      'loginState': 0,
      'status': 'offline',
      'logoutReason': reason,
      'explicitLogoutAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> safeHeartbeat({String source = 'heartbeat'}) async {
    try {
      await markHeartbeat(source: source);
    } catch (e) {
      debugPrint('[SessionState] heartbeat failed: $e');
    }
  }
}