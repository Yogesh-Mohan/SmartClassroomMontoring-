import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../services/attendance_service.dart';
import '../../services/monitor_service.dart';
import '../../services/session_state_service.dart';
import '../../services/timetable_monitor.dart';
import 'home/student_home_screen.dart';
import 'credits/credits_screen.dart';
import 'classroom/student_classroom_screen.dart';
import 'alerts/alerts_screen.dart';
import 'profile/student_profile_screen.dart';

class StudentShell extends StatefulWidget {
  final Map<String, dynamic> studentData;
  const StudentShell({super.key, required this.studentData});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  late final List<Widget> _pages;
  final ScreenMonitorService _monitorService = ScreenMonitorService();
  final TimetableMonitor _timetableMonitor = TimetableMonitor();
  Timer? _sessionHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final classCandidates = _buildClassCandidates();
    final studentLookupKeys = _buildStudentLookupKeys();
    final studentUID = _resolveStudentUid();
    _pages = [
      StudentHomeScreen(studentData: widget.studentData),
      StudentClassroomScreen(studentData: widget.studentData),
      CreditsScreen(studentData: widget.studentData),
      AlertsScreen(
        studentUID: studentUID,
        classCandidates: classCandidates,
        studentLookupKeys: studentLookupKeys,
      ),
      StudentProfileScreen(studentData: widget.studentData),
    ];

    // Start screen monitoring for this student
    _initializeMonitoring();
    _startSessionHeartbeat();
  }

  void _startSessionHeartbeat() {
    // Keep loginState=1 alive while app is active, even after reload/resume.
    SessionStateService.instance.safeHeartbeat(source: 'student_shell_init');
    _sessionHeartbeatTimer?.cancel();
    _sessionHeartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      SessionStateService.instance.safeHeartbeat(
        source: 'student_shell_periodic',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SessionStateService.instance.safeHeartbeat(
        source: 'student_shell_resumed',
      );
    }
  }

  Future<void> _initializeMonitoring() async {
    final hasPermissions = await _hasRequiredPermissions();
    if (!hasPermissions) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Usage Access + Notification permission required. Please grant permissions and login again.',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Do not force logout when permissions are missing.
      // Student can continue using the app; monitoring features stay disabled.
      return;
    }

    final studentId =
        widget.studentData['id'] ??
        widget.studentData['registrationNumber'] ??
        'unknown';
    final studentName =
      (widget.studentData['name'] ??
          widget.studentData['studentName'] ??
          widget.studentData['fullName'] ??
          widget.studentData['displayName'] ??
          'Student')
        .toString()
        .trim();
    final regNo =
        (widget.studentData['studentId'] ??
                widget.studentData['registrationNumber'] ??
                widget.studentData['regNo'] ??
                widget.studentData['rollNo'] ??
                '')
            .toString();

    final started = await _monitorService.startMonitoring(
      studentId,
      studentName,
      regNo: regNo,
    );
    debugPrint(
      started
          ? 'Screen monitoring started for: $studentName'
          : 'Failed to start screen monitoring',
    );

    // ── Create today's attendance record (duplicate-safe) ─────────────────
    try {
      await AttendanceService.instance.createAttendance(
        studentData: widget.studentData,
      );
    } catch (e) {
      debugPrint('[Shell] createAttendance error: $e');
    }

    if (started) {
      // Determine student's class for timetable lookup.
      // 'className' / 'class' / 'section' hold the actual class ID (e.g. CSE_AI_2025).
      // 'batch' is the admission year range (e.g. 2024-2028) — NOT the timetable key.
      // We pass ALL candidate values so TimetableMonitor can try each one.
      final candidates = <String>[
        if (widget.studentData['className'] != null)
          widget.studentData['className'].toString(),
        if (widget.studentData['class'] != null)
          widget.studentData['class'].toString(),
        if (widget.studentData['section'] != null)
          widget.studentData['section'].toString(),
        if (widget.studentData['course'] != null)
          widget.studentData['course'].toString(),
        if (widget.studentData['batch'] != null)
          widget.studentData['batch'].toString(),
      ];
      _timetableMonitor.start(candidates);
    }
  }

  String _resolveStudentUid() {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.trim().isNotEmpty) {
      return authUid.trim();
    }

    return (widget.studentData['uid'] ??
            widget.studentData['id'] ??
            widget.studentData['studentId'] ??
            widget.studentData['registrationNumber'] ??
            widget.studentData['regNo'] ??
            widget.studentData['rollNo'] ??
            '')
        .toString()
        .trim();
  }

  List<String> _buildClassCandidates() {
    final raw = <dynamic>[
      widget.studentData['className'],
      widget.studentData['class'],
      widget.studentData['section'],
      widget.studentData['course'],
      widget.studentData['batch'],
    ];
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      if (seen.add(text)) out.add(text);
    }
    return out;
  }

  List<String> _buildStudentLookupKeys() {
    final raw = <dynamic>[
      FirebaseAuth.instance.currentUser?.uid,
      widget.studentData['uid'],
      widget.studentData['id'],
      widget.studentData['studentId'],
      widget.studentData['registrationNumber'],
      widget.studentData['regNo'],
      widget.studentData['rollNo'],
      widget.studentData['email'],
      widget.studentData['gmail'],
    ];
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      if (seen.add(text)) out.add(text);
    }
    return out;
  }

  Future<bool> _hasRequiredPermissions() async {
    try {
      final usageGranted = await _monitorService.hasUsagePermission();
      if (!usageGranted) {
        return false;
      }

      final notificationSettings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return notificationSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          notificationSettings.authorizationStatus ==
              AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionHeartbeatTimer?.cancel();
    // Stop timetable monitor first, then the native service
    _timetableMonitor.stop();
    _monitorService.stopMonitoring();
    super.dispose();
  }

  static const _navItems = [
    _NavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
    _NavItem(
      Icons.calendar_month_rounded,
      Icons.calendar_month_outlined,
      'Attendance',
    ),
    _NavItem(
      Icons.workspace_premium_rounded,
      Icons.workspace_premium_outlined,
      'Credits',
    ),
    _NavItem(
      Icons.notifications_rounded,
      Icons.notifications_outlined,
      'Alerts',
    ),
    _NavItem(Icons.person_rounded, Icons.person_outlined, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050520),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: (bottomInset > 0 ? bottomInset : 6) + 6,
        top: 6,
      ),
      child: Row(
        children: List.generate(_navItems.length, (i) {
          final item = _navItems[i];
          final selected = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _currentIndex = i),
              child: AnimatedScale(
                scale: selected ? 1.0 : 0.9,
                duration: const Duration(milliseconds: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? item.activeIcon : item.icon,
                      size: 24,
                      color: selected
                          ? AppColors.lightBlue
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? AppColors.lightBlue
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: selected ? 20 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.lightBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData activeIcon;
  final IconData icon;
  final String label;
  const _NavItem(this.activeIcon, this.icon, this.label);
}
