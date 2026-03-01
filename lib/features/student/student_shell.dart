import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../models/student_alert_model.dart';
import '../../services/monitor_service.dart';
import '../../services/notification_service.dart';
import '../../services/timetable_monitor.dart';
import 'home/student_home_screen.dart';
import 'credits/credits_screen.dart';
import 'timetable/timetable_screen.dart';
import 'alerts/alerts_screen.dart';
import 'profile/student_profile_screen.dart';

class StudentShell extends StatefulWidget {
  final Map<String, dynamic> studentData;
  const StudentShell({super.key, required this.studentData});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _currentIndex = 0;
  int _openTasksSignal = 0;

  late List<Widget> _pages;
  final ScreenMonitorService _monitorService = ScreenMonitorService();
  final TimetableMonitor     _timetableMonitor = TimetableMonitor();
  late final List<String> _studentLookupKeys;

  @override
  void initState() {
    super.initState();
    _studentLookupKeys = _resolveStudentLookupKeys();
    _pages = [
      StudentHomeScreen(
        studentData: widget.studentData,
        openTasksSignal: _openTasksSignal,
      ),
      CreditsScreen(studentData: widget.studentData),
      TimetableScreen(studentData: widget.studentData),
      AlertsScreen(
        studentLookupKeys: _studentLookupKeys,
        onAlertTap: _handleStudentAlertTap,
      ),
      StudentProfileScreen(studentData: widget.studentData),
    ];
    
    // Start screen monitoring for this student
    _initializeMonitoring();
    _bootstrapStudentPushRouting();
  }

  Future<void> _bootstrapStudentPushRouting() async {
    await NotificationService().initialize();
    await NotificationService().requestPermissions();
    await NotificationService().registerFcmForegroundHandlers();
    NotificationService().setActionHandler(_handleNotificationAction);
  }

  List<String> _resolveStudentLookupKeys() {
    final d = widget.studentData;
    final raw = [
      d['uid'],
      d['id'],
      d['studentId'],
      d['registrationNumber'],
      d['regNo'],
      d['rollNo'],
      d['email'],
      d['gmail'],
    ];
    final seen = <String>{};
    final keys = <String>[];
    for (final value in raw) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      if (seen.add(text)) keys.add(text);
    }
    return keys;
  }

  void _openHomeAndTasks() {
    setState(() {
      _currentIndex = 0;
      _openTasksSignal++;
      _pages[0] = StudentHomeScreen(
        studentData: widget.studentData,
        openTasksSignal: _openTasksSignal,
      );
    });
  }

  void _handleStudentAlertTap(StudentAlert alert) {
    if (alert.type == StudentAlertType.taskAssigned) {
      _openHomeAndTasks();
    }
  }

  void _handleNotificationAction(NotificationAction action) {
    final type = action.type.trim().toLowerCase();
    if (type == 'task_assigned' || type == 'task_alert') {
      _openHomeAndTasks();
    }
  }
 
  Future<void> _initializeMonitoring() async {
    final studentId   = widget.studentData['id'] ??
        widget.studentData['registrationNumber'] ?? 'unknown';
    final studentName = widget.studentData['name'] ?? 'Student';
    final regNo       = (widget.studentData['studentId'] ??
        widget.studentData['registrationNumber'] ??
        widget.studentData['regNo'] ??
        widget.studentData['rollNo'] ??
        '').toString();

    // Check Usage Access permission — needed for foreground app detection.
    // Service still starts in fail-safe mode even without it.
    final hasPermission = await _monitorService.hasUsagePermission();
    if (!hasPermission && mounted) {
      _showUsagePermissionDialog();
    }

    final started = await _monitorService.startMonitoring(
      studentId,
      studentName,
      regNo: regNo,
    );
    debugPrint(started
        ? 'Screen monitoring started for: $studentName'
        : 'Failed to start screen monitoring');

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

  void _showUsagePermissionDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'This app needs Usage Access permission to monitor which apps '
          'are being used on the screen.\n\n'
          'Please enable it for "Smart Classroom" in the next screen.\n\n'
          'Go to: Settings → Apps → Special App Access → Usage Access',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _monitorService.requestUsagePermission();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Stop timetable monitor first, then the native service
    NotificationService().setActionHandler(null);
    _timetableMonitor.stop();
    _monitorService.stopMonitoring();
    super.dispose();
  }

  static const _navItems = [
    _NavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
    _NavItem(Icons.workspace_premium_rounded, Icons.workspace_premium_outlined, 'Credits'),
    _NavItem(Icons.calendar_month_rounded, Icons.calendar_month_outlined, 'Schedule'),
    _NavItem(Icons.notifications_rounded, Icons.notifications_outlined, 'Alerts'),
    _NavItem(Icons.person_rounded, Icons.person_outlined, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050520),
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1), width: 1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)
        ],
      ),
      padding: const EdgeInsets.only(bottom: 6, top: 6),
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
