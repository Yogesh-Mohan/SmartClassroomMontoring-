import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/session_state_service.dart';

class StudentAuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sign out the current student
  static Future<void> signOut({bool explicit = true}) async {
    if (explicit) {
      try {
        await SessionStateService.instance.markLoggedOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  /// Authenticates a student.
  /// 1. Signs in with Firebase Auth (email + password).
  /// 2. If the Firebase Auth account doesn't exist yet, auto-migrates from Firestore.
  /// 3. Fetches and returns the Firestore student profile.
  static Future<Map<String, dynamic>?> signIn(
    String email,
    String password,
  ) async {
    final String normalizedEmail = email.trim().toLowerCase();
    final String enteredPassword = password.trim();

    UserCredential credential;
    try {
      // ── Step 1: try Firebase Auth sign-in ──────────────────────────────────
      credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: enteredPassword,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        // ── Step 2: auto-migrate from Firestore password ────────────────────
        credential = await _migrateStudent(normalizedEmail, enteredPassword);
      } else {
        throw Exception(_authMessage(e.code));
      }
    }

    // ── Step 3: fetch Firestore profile ────────────────────────────────────
    final profile = await _fetchProfile(normalizedEmail, credential.user!.uid);
    try {
      await SessionStateService.instance.markLoggedIn(
        studentData: profile,
        source: 'student_auth_signin',
      );
    } catch (_) {}
    return profile;
  }

  /// First-time migration: verify password from Firestore, then create a
  /// Firebase Auth account so future logins use proper Firebase Auth.
  static Future<UserCredential> _migrateStudent(
    String email,
    String password,
  ) async {
    // Look up by 'gmail' first, then 'email'
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _firestore
          .collection('students')
          .where('gmail', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await _firestore
            .collection('students')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'Access denied. Fix your Firestore security rules in the Firebase Console.',
        );
      }
      throw Exception('Server error: ${e.message}');
    }

    if (snap.docs.isEmpty) {
      throw Exception('No student account found for that email address.');
    }

    final data = snap.docs.first.data();
    final storedPassword = (data['password'] ?? '').toString().trim();
    if (storedPassword.isEmpty || storedPassword != password) {
      throw Exception('Incorrect password. Please try again.');
    }

    // Create Firebase Auth account (one-time migration)
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_authMessage(e.code));
    }
  }

  /// Fetches the student Firestore document after successful Firebase Auth.
  static Future<Map<String, dynamic>> _fetchProfile(
    String email,
    String uid,
  ) async {
    try {
      // Try 'gmail' field first, then 'email'
      var snap = await _firestore
          .collection('students')
          .where('gmail', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await _firestore
            .collection('students')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
      }
      if (snap.docs.isEmpty) {
        throw Exception(
          'Student profile not found. Contact your administrator.',
        );
      }
      // Store the Firebase Auth UID in the Firestore doc for future rule-based security
      final doc = snap.docs.first;
      await doc.reference.update({'uid': uid}).catchError((_) {});
      return {'id': doc.id, ...doc.data()};
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'Access denied. Fix your Firestore security rules in the Firebase Console.',
        );
      }
      throw Exception('Could not load your profile: ${e.message}');
    }
  }

  static String _authMessage(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No account found for that email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your administrator.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return 'Sign-in failed ($code). Please try again.';
    }
  }
}
