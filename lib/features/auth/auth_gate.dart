import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_gradients.dart';
import '../admin/admin_shell.dart';
import '../role_select/role_select_screen.dart';
import '../student/student_shell.dart';

/// AuthGate checks Firebase Auth state on app launch.
/// - If a user is already signed in → fetch their profile (admin or student)
///   and navigate directly to the correct shell.
/// - If no user is signed in → show the RoleSelectScreen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndRoute();
  }

  Future<void> _checkAuthAndRoute() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Not logged in — go to role selection
      _goTo(const RoleSelectScreen());
      return;
    }

    final email = user.email?.toLowerCase().trim() ?? '';

    try {
      // ── Try admin first ────────────────────────────────────────────────────
      final adminData = await _fetchAdminProfile(email, user.uid);
      if (!mounted) return;
      if (adminData != null) {
        _goTo(AdminShell(adminData: adminData));
        return;
      }

      // ── Try student ────────────────────────────────────────────────────────
      final studentData = await _fetchStudentProfile(email, user.uid);
      if (!mounted) return;
      if (studentData != null) {
        _goTo(StudentShell(studentData: studentData));
        return;
      }

      // ── Profile not found in any collection — sign out and re-login ────────
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _goTo(const RoleSelectScreen());
    } catch (_) {
      // On any error (network, permissions) sign out and show login
      await FirebaseAuth.instance.signOut().catchError((_) {});
      if (!mounted) return;
      _goTo(const RoleSelectScreen());
    }
  }

  Future<Map<String, dynamic>?> _fetchAdminProfile(
      String email, String uid) async {
    try {
      var snap = await FirebaseFirestore.instance
          .collection('admins')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('admins')
            .where('gmail', isEqualTo: email)
            .limit(1)
            .get();
      }
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      // Keep uid field up-to-date
      await doc.reference.update({'uid': uid}).catchError((_) {});
      return {'id': doc.id, ...doc.data()};
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchStudentProfile(
      String email, String uid) async {
    try {
      var snap = await FirebaseFirestore.instance
          .collection('students')
          .where('gmail', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('students')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
      }
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      await doc.reference.update({'uid': uid}).catchError((_) {});
      return {'id': doc.id, ...doc.data()};
    } catch (_) {
      return null;
    }
  }

  void _goTo(Widget screen) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => screen,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Splash / loading screen while resolving auth state
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
              const SizedBox(height: 20),
              Text(
                'Smart Classroom',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
