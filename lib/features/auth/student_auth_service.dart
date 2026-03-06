import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentAuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns today's date key in YYYY_MM_DD format (matches AdminDashboardService)
  static String _todayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${y}_${m}_$d';
  }

  /// Writes (or refreshes) an attendance record for the student so the admin
  /// dashboard "Present Today" count updates immediately on login.
  static Future<void> _recordAttendance(
    String uid,
    Map<String, dynamic> studentData,
  ) async {
    try {
      final dateKey = _todayDateKey();
      final docId = '${uid}_$dateKey'; // unique per student per day

      final name = (studentData['name'] ?? studentData['studentName'] ?? '')
          .toString()
          .trim();
      final regNo =
          (studentData['regNo'] ??
                  studentData['registrationNumber'] ??
                  studentData['studentId'] ??
                  studentData['rollNo'] ??
                  '')
              .toString()
              .trim();
      final className =
          (studentData['className'] ??
                  studentData['class'] ??
                  studentData['section'] ??
                  studentData['department'] ??
                  studentData['course'] ??
                  '')
              .toString()
              .trim();

      await _firestore.collection('attendance').doc(docId).set({
        'studentUID': uid,
        'date': dateKey,
        'name': name,
        'studentName': name,
        'regNo': regNo,
        'className': className,
        'loginTime': FieldValue.serverTimestamp(),
        // logoutTime is intentionally NOT set here — its absence means "present"
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: attendance recording failure should not block login
    }
  }

  /// Sign out the current student
  static Future<void> signOut() async {
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

    // ── Step 3: fetch Firestore profile + record attendance ───────────────
    return _fetchProfile(normalizedEmail, credential.user!.uid);
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
      final profileData = {'id': doc.id, 'uid': uid, ...doc.data()};
      // ── Step 4: record attendance so admin sees student as Present Today ──
      await _recordAttendance(uid, profileData);
      return profileData;
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
