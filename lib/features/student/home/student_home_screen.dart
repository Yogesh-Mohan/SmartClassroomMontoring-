import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/tasks_service.dart';
import '../../../utils/date_helpers.dart';
import '../tasks/tasks_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;
  const StudentHomeScreen({super.key, required this.studentData});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

// ── Period model ─────────────────────────────────────────────────────────────
class _PeriodInfo {
  final String id;
  final String subject;
  final int startMinutes;
  final int endMinutes;
  final bool isBreak;
  _PeriodInfo({
    required this.id,
    required this.subject,
    required this.startMinutes,
    required this.endMinutes,
    required this.isBreak,
  });
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  late final TasksService _tasksService;
  late final Stream<Map<String, int>> _taskStatsStream;
  late final Stream<List<TaskWithSubmission>> _tasksListStream;
  late final Stream<int> _violationsStream;
  late final Stream<int> _streakStream;
  late final Stream<List<FlSpot>> _violationTrendStream;

  List<_PeriodInfo> _todayPeriods = [];
  bool _periodsLoading = true;

  String get _name => widget.studentData['name'] ?? 'Student';
  String get _studentId =>
      widget.studentData['studentId'] ??
      widget.studentData['registrationNumber'] ??
      widget.studentData['regNo'] ??
      '—';

  String get _studentUID {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) return uid;
    return (widget.studentData['uid'] ??
            widget.studentData['id'] ??
            widget.studentData['studentId'] ??
            '')
        .toString();
  }

  List<String> get _classCandidates {
    final raw = <dynamic>[
      widget.studentData['className'],
      widget.studentData['class'],
      widget.studentData['section'],
      widget.studentData['course'],
      widget.studentData['department'],
      widget.studentData['batch'],
      widget.studentData['classId'],
    ];
    final out = <String>[];
    final seen = <String>{};
    for (final v in raw) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && seen.add(s)) out.add(s);
    }
    return out;
  }

  List<String> get _studentLookupKeys {
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

  // ── Streak: consecutive attendance days up to today ─────────────────────────
  Stream<int> _buildStreakStream(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('attendance')
        .where('studentUID', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final dates = snap.docs
              .map((d) {
                final raw = d.data()['date'];
                if (raw is Timestamp) return raw.toDate();
                if (raw is String) return DateTime.tryParse(raw);
                return null;
              })
              .whereType<DateTime>()
              .map((dt) => DateTime(dt.year, dt.month, dt.day))
              .toSet();
          int streak = 0;
          var day = DateTime.now();
          day = DateTime(day.year, day.month, day.day);
          while (dates.contains(day)) {
            streak++;
            day = day.subtract(const Duration(days: 1));
          }
          return streak;
        });
  }

  // ── Violation trend: last 7 days ─────────────────────────────────────────────
  Stream<List<FlSpot>> _buildTrendStream(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    return FirebaseFirestore.instance
        .collection('violations')
        .where('studentUID', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final blocks = DateHelpers.getDayBlocksForStreak(7).reversed.toList();
          final counts = List<int>.filled(blocks.length, 0);
          for (final doc in snap.docs) {
            final data = doc.data();
            final raw =
                data['timestamp'] ??
                data['createdAt'] ??
                data['detectedAt'] ??
                data['date'];
            DateTime? dt;
            if (raw is Timestamp) dt = raw.toDate();
            if (raw is String) dt = DateTime.tryParse(raw);
            if (dt == null) continue;

            for (var i = 0; i < blocks.length; i++) {
              if (blocks[i].contains(dt)) {
                counts[i] = counts[i] + 1;
                break;
              }
            }
          }
          return List.generate(
            blocks.length,
            (i) => FlSpot(i.toDouble(), counts[i].toDouble()),
          );
        });
  }

  void _openTasksScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TasksScreen(
          studentUID: _studentUID,
          classCandidates: _classCandidates,
          studentLookupKeys: _studentLookupKeys,
        ),
      ),
    );
  }

  // ── Load today's timetable ───────────────────────────────────────────────────
  Future<void> _loadTodayPeriods() async {
    final classes = _classCandidates;
    if (classes.isEmpty) {
      if (mounted) setState(() => _periodsLoading = false);
      return;
    }
    final dayName = DateFormat('EEEE').format(DateTime.now());
    final dayCandidates = <String>{
      dayName,
      dayName.toLowerCase(),
      dayName.substring(0, 3),
      dayName.substring(0, 3).toLowerCase(),
    };
    try {
      QuerySnapshot<Map<String, dynamic>>? snap;
      for (final cls in classes) {
        for (final day in dayCandidates) {
          final candidate = await FirebaseFirestore.instance
              .collection('timetables')
              .doc(cls)
              .collection(day)
              .get();
          if (candidate.docs.isNotEmpty) {
            snap = candidate;
            break;
          }
        }
        if (snap != null) break;
      }

      // Fallback: if class mapping is inconsistent, discover a class doc that has today's periods.
      if (snap == null || snap.docs.isEmpty) {
        final allClasses = await FirebaseFirestore.instance
            .collection('timetables')
            .get();
        for (final classDoc in allClasses.docs) {
          for (final day in dayCandidates) {
            final candidate = await FirebaseFirestore.instance
                .collection('timetables')
                .doc(classDoc.id)
                .collection(day)
                .get();
            if (candidate.docs.isNotEmpty) {
              snap = candidate;
              break;
            }
          }
          if (snap != null && snap.docs.isNotEmpty) break;
        }
      }

      snap ??= await FirebaseFirestore.instance
          .collection('timetables')
          .doc(classes.first)
          .collection(dayName)
          .get();

      int parseTime(dynamic val) {
        if (val == null) return 0;
        if (val is num) return val.toInt();
        final s = val.toString().trim();

        final amPm = RegExp(
          r'^(\d{1,2}):(\d{2})\s*([aApP][mM])$',
        ).firstMatch(s);
        if (amPm != null) {
          var hour = int.tryParse(amPm.group(1)!) ?? 0;
          final minute = int.tryParse(amPm.group(2)!) ?? 0;
          final marker = amPm.group(3)!.toLowerCase();
          if (marker == 'pm' && hour < 12) hour += 12;
          if (marker == 'am' && hour == 12) hour = 0;
          return hour * 60 + minute;
        }

        if (s.contains(':')) {
          final p = s.split(':');
          if (p.length != 2) return 0;
          final hour = int.tryParse(p[0]) ?? 0;
          final minute = int.tryParse(p[1]) ?? 0;
          return hour * 60 + minute;
        }
        return int.tryParse(s) ?? 0;
      }

      final periods = snap.docs.map((doc) {
        final data = doc.data();
        return _PeriodInfo(
          id: doc.id,
          subject: data['subject'] ?? data['name'] ?? doc.id,
          startMinutes: parseTime(data['startTime'] ?? data['start']),
          endMinutes: parseTime(data['endTime'] ?? data['end']),
          isBreak:
              (data['type'] ?? '').toString().toLowerCase().contains('break') ||
              (data['subject'] ?? '').toString().toLowerCase().contains(
                'break',
              ),
        );
      }).toList()..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

      if (mounted) {
        setState(() {
          _todayPeriods = periods;
          _periodsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _periodsLoading = false);
    }
  }

  List<_PeriodInfo> _periodsForCurrentWindow() {
    if (_todayPeriods.isEmpty) return const <_PeriodInfo>[];

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Determine lunch window from actual break periods
    var lunchStartMinutes = 12 * 60; // default 12:00
    var lunchEndMinutes = 13 * 60; // default 13:00

    final lunchBreaks =
        _todayPeriods
            .where(
              (p) => p.isBreak && p.subject.toLowerCase().contains('lunch'),
            )
            .toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    if (lunchBreaks.isNotEmpty) {
      lunchStartMinutes = lunchBreaks.first.startMinutes;
      lunchEndMinutes = lunchBreaks.first.endMinutes > 0
          ? lunchBreaks.first.endMinutes
          : lunchStartMinutes + 60;
    }

    final eveningCutoff = 17 * 60; // 5:00 PM

    if (currentMinutes < lunchEndMinutes) {
      // Morning window: periods before lunch
      return _todayPeriods
          .where((p) => p.startMinutes < lunchStartMinutes)
          .toList();
    } else if (currentMinutes < eveningCutoff) {
      // Afternoon window: periods after lunch and before 5pm
      return _todayPeriods
          .where(
            (p) =>
                p.startMinutes >= lunchEndMinutes &&
                p.startMinutes < eveningCutoff,
          )
          .toList();
    } else {
      // Evening window: periods at or after 5pm
      return _todayPeriods
          .where((p) => p.startMinutes >= eveningCutoff)
          .toList();
    }
  }

  @override
  void initState() {
    super.initState();
    _tasksService = TasksService();
    final uid = _studentUID;

    _taskStatsStream = _tasksService.streamTaskStats(
      studentUID: uid,
      classCandidates: _classCandidates,
      studentLookupKeys: _studentLookupKeys,
    );

    _tasksListStream = uid.isEmpty
        ? Stream.value(const <TaskWithSubmission>[])
        : _tasksService
              .streamStudentAssignedTasks(
                studentUID: uid,
                classCandidates: _classCandidates,
                studentLookupKeys: _studentLookupKeys,
              )
              .map((items) => items.take(5).toList());

    _violationsStream = uid.isEmpty
        ? Stream.value(0)
        : FirebaseFirestore.instance
              .collection('violations')
              .where('studentUID', isEqualTo: uid)
              .snapshots()
              .map((snap) {
                var count = 0;
                for (final doc in snap.docs) {
                  final data = doc.data();
                  final raw =
                      data['timestamp'] ??
                      data['createdAt'] ??
                      data['detectedAt'] ??
                      data['date'];
                  DateTime? dt;
                  if (raw is Timestamp) dt = raw.toDate();
                  if (raw is String) dt = DateTime.tryParse(raw);
                  if (dt != null && DateHelpers.isInCurrentPeriod(dt)) {
                    count++;
                  }
                }
                return count;
              });

    _streakStream = _buildStreakStream(uid);
    _violationTrendStream = _buildTrendStream(uid);
    _loadTodayPeriods();
  }

  String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final visiblePeriods = _periodsForCurrentWindow();
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
            // ── Header ────────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _name.toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ID: $_studentId',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
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
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ).animate().fadeIn(),

            const SizedBox(height: 24),

            // ── Stats: Tasks | Streak | Violations ───────────────────────────
            StreamBuilder<Map<String, int>>(
              stream: _taskStatsStream,
              builder: (context, taskSnap) {
                final total = taskSnap.data?['total'] ?? 0;
                final done = taskSnap.data?['completed'] ?? 0;
                return StreamBuilder<int>(
                  stream: _streakStream,
                  builder: (context, streakSnap) {
                    final streak = streakSnap.data ?? 0;
                    return StreamBuilder<int>(
                      stream: _violationsStream,
                      builder: (context, violSnap) {
                        final violations = violSnap.data ?? 0;
                        return Row(
                          children: [
                            _StatCard(
                              label: 'Tasks',
                              value:
                                  taskSnap.connectionState ==
                                      ConnectionState.waiting
                                  ? '...'
                                  : '$done/$total',
                              icon: Icons.check_circle_rounded,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 12),
                            _StatCard(
                              label: 'Streak',
                              value: '$streak days',
                              icon: Icons.local_fire_department_rounded,
                              color: const Color(0xFF00D4FF),
                            ),
                            const SizedBox(width: 12),
                            _StatCard(
                              label: 'Violations',
                              value: '$violations',
                              icon: Icons.warning_rounded,
                              color: violations > 0
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                          ],
                        ).animate().fadeIn(delay: 150.ms);
                      },
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 20),

            // ── My Tasks & Goals ──────────────────────────────────────────────
            StreamBuilder<List<TaskWithSubmission>>(
              stream: _tasksListStream,
              builder: (context, snap) {
                final items = snap.data ?? [];
                final pending = items
                    .where((t) => t.status.name != 'accepted')
                    .length;
                final hasPending =
                    snap.connectionState != ConnectionState.waiting &&
                    pending > 0;

                final gradient = hasPending
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFD32F2F), Color(0xFFFF6B6B)],
                      )
                    : AppGradients.blueGradient;

                final shadowColor = hasPending
                    ? const Color(0xFFFF0000)
                    : const Color(0xFF2E5BFF);

                final icon = hasPending
                    ? Icons.assignment_late_rounded
                    : Icons.check_circle_outline_rounded;

                final subtitleText =
                    snap.connectionState == ConnectionState.waiting
                    ? 'Loading...'
                    : hasPending
                    ? '$pending task${pending > 1 ? 's' : ''} pending!'
                    : 'All tasks completed!';

                return GestureDetector(
                  onTap: _openTasksScreen,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'My Tasks & Goals',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                subtitleText,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.08, end: 0);
              },
            ),

            const SizedBox(height: 20),

            // ── Violation Trend Last 7 Days ────────────────────────────────────
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Violation Trend (Last 7 Days)',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(
                        '11 PM Reset',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<FlSpot>>(
                    stream: _violationTrendStream,
                    builder: (context, snap) {
                      final spots = (snap.data != null && snap.data!.isNotEmpty)
                          ? snap.data!
                          : List.generate(7, (i) => FlSpot(i.toDouble(), 0));
                      final maxY = spots
                          .map((s) => s.y)
                          .fold<double>(4, (a, b) => a > b ? a : b);
                      final now = DateTime.now();
                      final labels = List.generate(7, (i) {
                        final d = now.subtract(Duration(days: 6 - i));
                        return DateFormat('d').format(d);
                      });

                      return SizedBox(
                        height: 150,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: maxY + 1,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 1,
                              getDrawingHorizontalLine: (v) => FlLine(
                                color: Colors.white.withValues(alpha: 0.06),
                                strokeWidth: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  getTitlesWidget: (v, _) {
                                    if (v == 50) {
                                      return Text(
                                        '50',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: AppColors.textSecondary,
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= 7) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        labels[i],
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                color: const Color(0xFFFFB020),
                                barWidth: 3,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, _, _, _) =>
                                      FlDotCirclePainter(
                                        radius: 6,
                                        color: Colors.white,
                                        strokeWidth: 3,
                                        strokeColor: spot.y <= 1
                                            ? AppColors.success
                                            : const Color(0xFFFFB020),
                                      ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      const Color(
                                        0xFFFFB020,
                                      ).withValues(alpha: 0.28),
                                      const Color(
                                        0xFFFFB020,
                                      ).withValues(alpha: 0),
                                    ],
                                  ),
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
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.08, end: 0),

            const SizedBox(height: 20),

            // ── Today's Schedule ──────────────────────────────────────────────
            Text(
              "Today's Schedule",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ).animate().fadeIn(delay: 380.ms),
            const SizedBox(height: 12),

            if (_periodsLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (_todayPeriods.isEmpty)
              GlassCard(
                child: Text(
                  'No schedule found for today.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else if (visiblePeriods.isEmpty)
              GlassCard(
                child: Text(
                  'No periods found for this time of day.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ..._buildGroupedSchedule(visiblePeriods),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSchedule(List<_PeriodInfo> periods) {
    // Determine current window label
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Figure out lunch boundaries from timetable
    var lunchStartMinutes = 12 * 60;
    var lunchEndMinutes = 13 * 60;
    final lunchBreaks =
        _todayPeriods
            .where(
              (p) => p.isBreak && p.subject.toLowerCase().contains('lunch'),
            )
            .toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    if (lunchBreaks.isNotEmpty) {
      lunchStartMinutes = lunchBreaks.first.startMinutes;
      lunchEndMinutes = lunchBreaks.first.endMinutes > 0
          ? lunchBreaks.first.endMinutes
          : lunchStartMinutes + 60;
    }
    const eveningCutoff = 17 * 60;

    String sectionLabel;
    if (currentMinutes < lunchEndMinutes) {
      sectionLabel = 'Before Lunch';
    } else if (currentMinutes < eveningCutoff) {
      sectionLabel = 'After Lunch';
    } else {
      sectionLabel = 'Evening';
    }

    final out = <Widget>[];
    var index = 0;

    if (periods.isNotEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            sectionLabel,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
      for (final period in periods) {
        final cur = now.hour * 60 + now.minute;
        final isNow = cur >= period.startMinutes && cur < period.endMinutes;
        final isPast = cur >= period.endMinutes;
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PeriodTile(
              subject: period.subject,
              timeRange:
                  '${_fmt(period.startMinutes)} – ${_fmt(period.endMinutes)}',
              isBreak: period.isBreak,
              isNow: isNow,
              isPast: isPast,
            ).animate().fadeIn(delay: (400 + index * 50).ms),
          ),
        );
        index++;
      }
    }

    return out;
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


// ── Period Tile ───────────────────────────────────────────────────────────────
class _PeriodTile extends StatelessWidget {
  final String subject;
  final String timeRange;
  final bool isBreak;
  final bool isNow;
  final bool isPast;

  const _PeriodTile({
    required this.subject,
    required this.timeRange,
    required this.isBreak,
    required this.isNow,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    // Match the screenshot's yellow accent style, but keep success for active items
    final Color accent = isNow ? AppColors.success : const Color(0xFFFFB020);

    return Opacity(
      opacity: isPast && !isNow ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              margin: const EdgeInsets.only(right: 16),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeRange,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            if (isNow)
              _badge('Now', AppColors.success)
            else
              Text(
                'N/A',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
