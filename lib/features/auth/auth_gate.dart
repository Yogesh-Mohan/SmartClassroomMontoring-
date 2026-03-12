import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_gradients.dart';
import '../../services/monitor_service.dart';
import '../advisor/advisor_dashboard.dart';
import '../admin/admin_shell.dart';
import '../role_select/role_select_screen.dart';
import '../student/student_shell.dart';
import '../teacher/teacher_dashboard.dart';

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
  late final Future<Widget> _initialScreenFuture;
  final ScreenMonitorService _monitorService = ScreenMonitorService();

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _resolveInitialScreen();
  }

  Future<Widget> _resolveInitialScreen() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const RoleSelectScreen();
    }

    try {
      final roleProfile = await _fetchUserRole(user.uid);
      if (roleProfile != null) {
        final role = roleProfile['role'];
        final data = roleProfile['data'] as Map<String, dynamic>;
        if (role == 'student') {
          final allowed = await _hasRequiredStudentPermissions();
          if (!allowed) {
            await FirebaseAuth.instance.signOut().catchError((_) {});
            return const RoleSelectScreen();
          }
          return StudentShell(studentData: data);
        }
        if (role == 'admin') {
          return AdminShell(adminData: data);
        }
        if (role == 'advisor') {
          return AdvisorDashboard(advisorData: data);
        }
        if (role == 'teacher') {
          return TeacherDashboard(teacherData: data);
        }
      }

      final email = user.email?.toLowerCase().trim() ?? '';

      // ── Backward compatible fallbacks ──────────────────────────────────────
      final adminData = await _fetchAdminProfile(email, user.uid);
      if (adminData != null) {
        return AdminShell(adminData: adminData);
      }

      final studentData = await _fetchStudentProfile(email, user.uid);
      if (studentData != null) {
        final allowed = await _hasRequiredStudentPermissions();
        if (!allowed) {
          await FirebaseAuth.instance.signOut().catchError((_) {});
          return const RoleSelectScreen();
        }
        return StudentShell(studentData: studentData);
      }

      // ── Profile not found in any collection — sign out and re-login ────────
      await FirebaseAuth.instance.signOut();
      return const RoleSelectScreen();
    } catch (_) {
      // On any error (network, permissions) sign out and show login
      await FirebaseAuth.instance.signOut().catchError((_) {});
      return const RoleSelectScreen();
    }
  }

  Future<Map<String, dynamic>?> _fetchAdminProfile(
    String email,
    String uid,
  ) async {
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
    String email,
    String uid,
  ) async {
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

  Future<Map<String, dynamic>?> _fetchUserRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data() ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase().trim();
      if (role.isEmpty) return null;
      return {
        'role': role,
        'data': {'id': uid, ...data},
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasRequiredStudentPermissions() async {
    try {
      final usageGranted = await _monitorService.hasUsagePermission();
      if (!usageGranted) return false;

      final notificationSettings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final notificationGranted =
          notificationSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          notificationSettings.authorizationStatus ==
              AuthorizationStatus.provisional;
      return notificationGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initialScreenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return snapshot.data!;
        }

        // Splash / loading screen while resolving auth state
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppGradients.primaryVertical,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
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
      },
    );
  }
}
