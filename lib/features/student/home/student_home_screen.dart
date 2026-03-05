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
      widget.studentData['batch'],
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
        final raw = data['timestamp'] ??
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
      return List.generate(blocks.length,
          (i) => FlSpot(i.toDouble(), counts[i].toDouble()));
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

      snap ??= await FirebaseFirestore.instance
          .collection('timetables')
          .doc(classes.first)
          .collection(dayName)
          .get();

      int parseTime(dynamic val) {
        if (val == null) return 0;
        final s = val.toString().trim();
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
          isBreak: (data['type'] ?? '').toString().toLowerCase().contains('break') ||
              (data['subject'] ?? '').toString().toLowerCase().contains('break'),
        );
      }).toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

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

    final currentMinutes = DateTime.now().hour * 60 + DateTime.now().minute;
    var lunchCutoff = 13 * 60;

    final lunchBreaks = _todayPeriods
        .where((p) =>
            p.isBreak && p.subject.toLowerCase().contains('lunch'))
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    if (lunchBreaks.isNotEmpty) {
      final lunch = lunchBreaks.first;
      lunchCutoff = lunch.endMinutes > 0 ? lunch.endMinutes : lunch.startMinutes;
    }

    if (currentMinutes < lunchCutoff) {
      return _todayPeriods.where((p) => p.startMinutes < lunchCutoff).toList();
    }

    return _todayPeriods.where((p) => p.startMinutes >= lunchCutoff).toList();
  }

  @override
  void initState() {
    super.initState();
    _tasksService = TasksService();
    final uid = _studentUID;

    _taskStatsStream = _tasksService.streamTaskStats(
      studentUID: uid,
      classCandidates: _classCandidates,
    );

    _tasksListStream = uid.isEmpty
      ? Stream.value(const <TaskWithSubmission>[])
      : _tasksService.streamStudentAssignedTasks(
        studentUID: uid,
        classCandidates: _classCandidates,
        ).map((items) => items.take(5).toList());

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
                final raw = data['timestamp'] ??
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
                      Text(greeting,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: AppColors.textSecondary)),
                      Text(_name,
                          style: GoogleFonts.poppins(
                              fontSize: 20,
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
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white, size: 24),
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
                              value: '$done/$total',
                              icon: Icons.check_circle_rounded,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 12),
                            _StatCard(
                              label: 'Streak',
                              value: '${streak}days',
                              icon: Icons.local_fire_department_rounded,
                              color: Colors.orange,
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
            GestureDetector(
              onTap: _openTasksScreen,
              child: GlassCard(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        const Icon(Icons.track_changes_rounded,
                            color: AppColors.lightBlue, size: 18),
                        const SizedBox(width: 8),
                        Text('My Tasks & Goals',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ]),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          color: AppColors.textSecondary, size: 14),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<TaskWithSubmission>>(
                    stream: _tasksListStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final items = snap.data ?? const <TaskWithSubmission>[];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No tasks assigned yet.',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        );
                      }
                      return Column(
                        children: items.map((item) {
                          final title = item.task.title.trim().isEmpty
                              ? 'Task'
                              : item.task.title.trim();
                          final statusName = item.status.name;
                          final status = statusName == 'accepted'
                              ? 'completed'
                              : statusName == 'rejected'
                                  ? 'overdue'
                                  : 'pending';
                          return _TaskRow(title: title, status: status);
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            )).animate().fadeIn(delay: 200.ms).slideY(begin: 0.08, end: 0),

            const SizedBox(height: 20),

            // ── Violation Trend Last 7 Days ────────────────────────────────────
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Violation Trend (Last 7 Days)',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                      Text('11 PM Reset',
                          style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<FlSpot>>(
                    stream: _violationTrendStream,
                    builder: (context, snap) {
                      final spots = (snap.data != null && snap.data!.isNotEmpty)
                          ? snap.data!
                          : List.generate(
                              7, (i) => FlSpot(i.toDouble(), 0));
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
                              leftTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
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
                                      child: Text(labels[i],
                                          style: GoogleFonts.poppins(
                                              fontSize: 9,
                                              color:
                                                  AppColors.textSecondary)),
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
                                    color: spot.y <= 1
                                        ? AppColors.success
                                        : const Color(0xFFFFB020),
                                    strokeWidth: 2,
                                    strokeColor: Colors.white,
                                  ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      const Color(0xFFFFB020)
                                          .withValues(alpha: 0.28),
                                      const Color(0xFFFFB020)
                                          .withValues(alpha: 0),
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
            Text("Today's Schedule",
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)).animate().fadeIn(delay: 380.ms),
            const SizedBox(height: 12),

            if (_periodsLoading)
              const Center(
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (_todayPeriods.isEmpty)
              GlassCard(
                child: Text('No schedule found for today.',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textSecondary)),
              )
            else if (visiblePeriods.isEmpty)
              GlassCard(
                child: Text('No periods found for this time of day.',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textSecondary)),
              )
            else
              ..._buildGroupedSchedule(visiblePeriods),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSchedule(List<_PeriodInfo> periods) {
    final morning = <_PeriodInfo>[];
    final afterLunch = <_PeriodInfo>[];
    final evening = <_PeriodInfo>[];

    for (final period in periods) {
      final hour = period.startMinutes ~/ 60;
      if (hour < 12) {
        morning.add(period);
      } else if (hour < 17) {
        afterLunch.add(period);
      } else {
        evening.add(period);
      }
    }

    final out = <Widget>[];
    var index = 0;
    void addSection(String title, List<_PeriodInfo> items) {
      if (items.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
      ));
      for (final period in items) {
        final now = DateTime.now();
        final cur = now.hour * 60 + now.minute;
        final isNow = cur >= period.startMinutes && cur < period.endMinutes;
        final isPast = cur >= period.endMinutes;
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PeriodTile(
              subject: period.subject,
              timeRange: '${_fmt(period.startMinutes)} – ${_fmt(period.endMinutes)}',
              isBreak: period.isBreak,
              isNow: isNow,
              isPast: isPast,
            ).animate().fadeIn(delay: (400 + index * 50).ms),
          ),
        );
        index++;
      }
      out.add(const SizedBox(height: 6));
    }

    addSection('Morning', morning);
    addSection('After Lunch', afterLunch);
    addSection('Evening', evening);

    if (out.isNotEmpty && out.last is SizedBox) {
      out.removeLast();
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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

// ── Task Row ─────────────────────────────────────────────────────────────────
class _TaskRow extends StatelessWidget {
  final String title;
  final String status;
  const _TaskRow({required this.title, required this.status});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String badge;
    switch (status.toLowerCase()) {
      case 'completed':
      case 'done':
        badgeColor = AppColors.success;
        badge = 'Done';
        break;
      case 'overdue':
        badgeColor = AppColors.danger;
        badge = 'Overdue';
        break;
      default:
        badgeColor = Colors.orange;
        badge = 'Pending';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: badgeColor.withValues(alpha: 0.5)),
            ),
            child: Text(badge,
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: badgeColor,
                    fontWeight: FontWeight.w600)),
          ),
        ],
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
    final Color accent = isNow
        ? AppColors.success
        : isBreak
            ? Colors.orange
            : AppColors.lightBlue;

    return Opacity(
      opacity: isPast && !isNow ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isNow
              ? AppColors.success.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: accent.withValues(alpha: isNow ? 0.6 : 0.25),
              width: isNow ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2)),
              margin: const EdgeInsets.only(right: 12),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text(timeRange,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (isNow)
              _badge('Now', AppColors.success)
            else
              _badge(isBreak ? 'Break' : 'Class Time',
                  isBreak ? Colors.orange : AppColors.lightBlue),
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
        child: Text(text,
            style: GoogleFonts.poppins(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}




