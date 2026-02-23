import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminAuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sign out the current admin
  static Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Authenticates an admin.
  /// 1. Signs in with Firebase Auth (email + password).
  /// 2. If the Firebase Auth account doesn't exist yet, auto-migrates from Firestore.
  /// 3. Fetches and returns the Firestore admin profile.
  static Future<Map<String, dynamic>?> signIn(String email, String password) async {
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
        credential = await _migrateAdmin(normalizedEmail, enteredPassword);
      } else {
        throw Exception(_authMessage(e.code));
      }
    }

    // ── Step 3: fetch Firestore profile ────────────────────────────────────
    return _fetchProfile(normalizedEmail, credential.user!.uid);
  }

  /// First-time migration: verify password from Firestore, then create a
  /// Firebase Auth account so future logins use proper Firebase Auth.
  static Future<UserCredential> _migrateAdmin(
      String email, String password) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _firestore
          .collection('admins')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await _firestore
            .collection('admins')
            .where('gmail', isEqualTo: email)
            .limit(1)
            .get();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
            'Access denied. Fix your Firestore security rules in the Firebase Console.');
      }
      throw Exception('Server error: \${e.message}');
    }

    if (snap.docs.isEmpty) {
      throw Exception('No admin account found for that email address.');
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

  /// Fetches the admin Firestore document after successful Firebase Auth.
  static Future<Map<String, dynamic>> _fetchProfile(
      String email, String uid) async {
    try {
      var snap = await _firestore
          .collection('admins')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await _firestore
            .collection('admins')
            .where('gmail', isEqualTo: email)
            .limit(1)
            .get();
      }
      if (snap.docs.isEmpty) {
        throw Exception('Admin profile not found. Contact your administrator.');
      }
      final doc = snap.docs.first;
      await doc.reference.update({'uid': uid}).catchError((_) {});
      return {'id': doc.id, ...doc.data()};
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
            'Access denied. Fix your Firestore security rules in the Firebase Console.');
      }
      throw Exception('Could not load admin profile: \${e.message}');
    }
  }

  static String _authMessage(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No admin account found for that email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact the system owner.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return 'Sign-in failed ($code). Please try again.';
    }
  }
}
