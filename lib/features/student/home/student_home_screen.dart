import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/tasks_service.dart';
import '../../../services/violations_stats_service.dart';
import '../../../services/timetable_service.dart';
import '../../../models/period_model.dart';
import '../tasks/tasks_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;
  const StudentHomeScreen({super.key, required this.studentData});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  static const int _violationAlertThreshold = 10;

  late final TasksService _tasksService;
  late final ViolationsStatsService _violationsService;
  late final TimetableService _timetableService;
  late final String _studentUID;
  /// The ID stored in the violations collection's studentUID field.
  /// monitor_service.dart saves violations using the student's Firestore doc ID
  /// (registration number) NOT the Firebase Auth UID, so we must use that here.
  late final String _violationStudentId;
  late final String _classId;
  late final List<String> _classCandidates;
  late final List<String> _studentLookupKeys;
  late final Future<DailySchedule> _dailySchedule;

  @override
  void initState() {
    super.initState();
    _tasksService = TasksService();
    _violationsService = ViolationsStatsService();
    _timetableService = TimetableService();
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final profileUid = widget.studentData['uid']?.toString();
    _studentUID = (authUid != null && authUid.trim().isNotEmpty)
        ? authUid.trim()
        : (profileUid ?? '').trim();

    // Violations are stored with the Firestore doc ID (reg number) as studentUID.
    // student_shell.dart passes studentData['id'] ?? studentData['registrationNumber']
    // to startMonitoring(), which saves it as the violations 'studentUID' field.
    // We must query by the same value, NOT the Firebase Auth UID.
    final d = widget.studentData;
    _violationStudentId = (d['id'] ??
            d['registrationNumber'] ??
            d['regNo'] ??
            d['rollNo'] ??
            d['studentId'] ??
            _studentUID)
        .toString()
        .trim();

    _classCandidates = _resolveClassCandidates();
    _studentLookupKeys = _resolveStudentLookupKeys();
    _classId = _classCandidates.isNotEmpty ? _classCandidates.first : '';

    if (_classId.isNotEmpty) {
      _dailySchedule = _timetableService.getDailySchedule(
        classId: _classId,
        classCandidates: _classCandidates,
      );
    } else {
      // Handle case where classId is not available
      _dailySchedule = Future.value(DailySchedule(morning: [], afternoon: []));
    }
  }

  List<String> _resolveClassCandidates() {
    final d = widget.studentData;
    final raw = [
      d['className'],
      d['ClassName'],
      d['class'],
      d['Class'],
      d['classId'],
      d['class_id'],
      d['section'],
      d['Section'],
      d['course'],
      d['department'],
      d['dept'],
      d['batch'],
      d['year'],
    ];

    final seen = <String>{};
    final out = <String>[];
    for (final value in raw) {
      if (value == null) continue;
      final s = value.toString().trim();
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  String get _name => widget.studentData['name'] ?? 'Student';
  String get _studentId => widget.studentData['studentId'] ?? '—';

  List<String> _resolveStudentLookupKeys() {
    final d = widget.studentData;
    final raw = [
      _studentUID,
      d['uid'],
      d['id'],
      d['studentId'],
      d['registrationNumber'],
      d['regNo'],
      d['rollNo'],
      d['gmail'],
      d['email'],
    ];

    final seen = <String>{};
    final out = <String>[];
    for (final value in raw) {
      if (value == null) continue;
      final s = value.toString().trim();
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 18
            ? 'Good Afternoon'
            : 'Good Evening';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                      Text(_name,
                          style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      Text('ID: $_studentId',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.blueGradient,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.lightBlue.withValues(alpha: 0.4),
                          blurRadius: 12)
                    ],
                  ),
                  child:
                      const Icon(Icons.person_rounded, color: Colors.white, size: 24),
                ),
              ],
            ).animate().fadeIn(),

            const SizedBox(height: 24),

            // Stats row - Real-time data from Firestore
            Row(
              children: [
                // Tasks Card
                Expanded(
                  child: StreamBuilder<Map<String, int>>(
                    stream: _tasksService.streamTaskStats(
                      studentUID: _studentUID,
                      classCandidates: _classCandidates,
                      studentLookupKeys: _studentLookupKeys,
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return _StatCard(
                          'Tasks',
                          '...',
                          Icons.task_alt_rounded,
                          AppColors.success,
                        );
                      }
                      final completed = snapshot.data!['completed'] ?? 0;
                      final total = snapshot.data!['total'] ?? 0;
                      return _StatCard(
                        'Tasks',
                        '$completed/$total',
                        Icons.task_alt_rounded,
                        AppColors.success,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 14),
                
                // Behavior Streak Card
                Expanded(
                  child: FutureBuilder<int>(
                    future: _violationsService.calculateBehaviorStreak(_violationStudentId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return _StatCard(
                          'Streak',
                          '...',
                          Icons.local_fire_department_rounded,
                          AppColors.lightBlue,
                        );
                      }
                      return _StatCard(
                        'Streak',
                        '${snapshot.data} days',
                        Icons.local_fire_department_rounded,
                        AppColors.lightBlue,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 14),
                
                // Violations Today Card (resets at 11 PM)
                Expanded(
                  child: StreamBuilder<int>(
                    stream: _violationsService.streamTodayViolations(_violationStudentId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return _StatCard(
                          'Violations',
                          '...',
                          Icons.warning_amber_rounded,
                          AppColors.warning,
                        );
                      }
                      final count = snapshot.data ?? 0;
                      return _StatCard(
                        'Violations',
                        count.toString(),
                        Icons.warning_amber_rounded,
                        count == 0 ? AppColors.success : AppColors.warning,
                      );
                    },
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 16),

            // 🚨 High-violation alert: shown when today's violations reach 10+
            StreamBuilder<int>(
              stream: _violationsService.streamTodayViolations(_violationStudentId),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                if (count < _violationAlertThreshold) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_rounded, color: AppColors.danger, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '⚠️ Alert: $count Rule Violations Today!',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
                                ),
                              ),
                              Text(
                                'You have broken the phone rule $count times today. Please follow the classroom rules.',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().shake(),
                );
              },
            ),

            // Quick Access to Tasks
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TasksScreen(
                      studentUID: _studentUID,
                      classCandidates: _classCandidates,
                      studentLookupKeys: _studentLookupKeys,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppGradients.blueGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.lightBlue.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.task_alt_rounded, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Tasks & Goals',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          StreamBuilder<Map<String, int>>(
                            stream: _tasksService.streamTaskStats(
                              studentUID: _studentUID,
                              classCandidates: _classCandidates,
                              studentLookupKeys: _studentLookupKeys,
                            ),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return Text(
                                  'Loading...',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                );
                              }
                              final completed = snapshot.data!['completed'] ?? 0;
                              final total = snapshot.data!['total'] ?? 0;
                              return Text(
                                total == 0 
                                    ? 'No task assigned by admin yet'
                                    : '$completed of $total approved',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1, end: 0),

            const SizedBox(height: 24),

            // Violation Trend Chart
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Violation Trend (Last 7 Days)',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      Text('11 PM Reset',
                          style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<Map<String, int>>(
                    future: _violationsService.getViolationsByDay(_violationStudentId, 7),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox(
                          height: 140,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.lightBlue,
                            ),
                          ),
                        );
                      }

                      final violationsByDay = snapshot.data!;
                      final values = violationsByDay.values.toList().reversed.toList();
                      final keys = violationsByDay.keys.toList().reversed.toList();
                      
                      // Create chart spots
                      final spots = <FlSpot>[];
                      for (int i = 0; i < values.length && i < 7; i++) {
                        spots.add(FlSpot(i.toDouble(), values[i].toDouble()));
                      }

                      // Find max value for y-axis scaling
                      final maxValue = values.isEmpty ? 10.0 : values.reduce((a, b) => a > b ? a : b).toDouble();
                      final chartMax = maxValue < 5 ? 10.0 : maxValue + 2;

                      return SizedBox(
                        height: 140,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: chartMax,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: chartMax / 5,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  getTitlesWidget: (value, meta) {
                                    if (value == meta.max || value == meta.min) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      value.toInt().toString(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        color: AppColors.textSecondary,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= keys.length) {
                                      return const SizedBox.shrink();
                                    }
                                    // Show shortened date (e.g., "Feb 28" -> "28")
                                    final dateStr = keys[i].split(' ').last;
                                    return Text(dateStr,
                                        style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            color: AppColors.textSecondary));
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                color: AppColors.warning,
                                barWidth: 3,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, _, _, _) =>
                                      FlDotCirclePainter(
                                    radius: 4,
                                    color: spot.y == 0 ? AppColors.success : AppColors.warning,
                                    strokeWidth: 2,
                                    strokeColor: Colors.white,
                                  ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: AppColors.warning.withValues(alpha: 0.15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1, end: 0),

            const SizedBox(height: 20),

            // Today's classes
            Text("Today's Schedule",
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white))
                .animate().fadeIn(delay: 350.ms),
            const SizedBox(height: 12),
            _buildSchedule(),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedule() {
    if (_classId.isEmpty) {
      return _buildEmptySchedule("Timetable not configured.");
    }

    return FutureBuilder<DailySchedule>(
      future: _dailySchedule,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: AppColors.lightBlue),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildEmptySchedule("Could not load schedule.");
        }

        final schedule = snapshot.data!;
        final now = DateTime.now();
        final nowMinutes = now.hour * 60 + now.minute;
        final lunchMinutes = schedule.lunchBreakTime.hour * 60 + schedule.lunchBreakTime.minute;
        final isMorning = nowMinutes < lunchMinutes; // Before actual lunch break

        final periodsToShow = isMorning ? schedule.morning : schedule.afternoon;
        final title = isMorning ? 'Before Lunch' : 'After Lunch';

        if (schedule.isEmpty) {
          return _buildEmptySchedule("No classes scheduled for today!");
        }
        
        if (periodsToShow.isEmpty) {
          return _buildEmptySchedule(isMorning ? 'No more classes before lunch.' : 'No classes scheduled after lunch.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Padding(
               padding: const EdgeInsets.only(bottom: 8.0),
               child: Text(title, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
             ),
            ...periodsToShow.map((period) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ClassTile(period: period).animate().fadeIn(delay: 400.ms),
                )),
          ],
        );
      },
    );
  }

  Widget _buildEmptySchedule(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }
}

class _ClassTile extends StatelessWidget {
  final Period period;
  const _ClassTile({required this.period});

  // Simple hash function to get a color from a string
  Color _getColorForSubject(String subject) {
    final hash = subject.hashCode;
    // Use a predefined list of colors to cycle through
    final colors = [
      AppColors.lightBlue,
      AppColors.success,
      AppColors.warning,
      Colors.purple.shade300,
      Colors.orange.shade400,
      Colors.teal.shade300,
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColorForSubject(period.subject);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 40, color: color,
              margin: const EdgeInsets.only(right: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(period.subject,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(period.formattedTime,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(period.room,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);


  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 10, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
