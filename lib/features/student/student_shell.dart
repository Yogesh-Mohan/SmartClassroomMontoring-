import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../services/monitor_service.dart';
import 'home/student_home_screen.dart';
import 'attendance/attendance_screen.dart';
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

  late final List<Widget> _pages;
  final ScreenMonitorService _monitorService = ScreenMonitorService();

  @override
  void initState() {
    super.initState();
    _pages = [
      StudentHomeScreen(studentData: widget.studentData),
      AttendanceScreen(studentData: widget.studentData),
      const TimetableScreen(),
      const AlertsScreen(),
      StudentProfileScreen(studentData: widget.studentData),
    ];
    
    // Start screen monitoring for this student
    _initializeMonitoring();
  }

  Future<void> _initializeMonitoring() async {
    final studentId = widget.studentData['id'] ??
        widget.studentData['registrationNumber'] ?? 'unknown';
    final studentName = widget.studentData['name'] ?? 'Student';

    // Check Usage Access permission — needed for foreground app detection.
    // Service still starts in fail-safe mode even without it.
    final hasPermission = await _monitorService.hasUsagePermission();
    if (!hasPermission && mounted) {
      _showUsagePermissionDialog();
    }

    final started = await _monitorService.startMonitoring(studentId, studentName);
    debugPrint(started
        ? 'Screen monitoring started for: $studentName'
        : 'Failed to start screen monitoring');
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
    // Stop monitoring when student logs out or app closes
    _monitorService.stopMonitoring();
    super.dispose();
  }

  static const _navItems = [
    _NavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
    _NavItem(Icons.event_available_rounded, Icons.event_available_outlined, 'Attendance'),
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
