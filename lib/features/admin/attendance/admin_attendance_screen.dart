import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/smart_attendance_service.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final SmartAttendanceService _service = SmartAttendanceService.instance;
  StreamSubscription<AttendanceSession?>? _sessionSubscription;

  String? _selectedPeriod;
  AttendanceSession? _session;
  String? _feedback;
  bool _loading = false;
  bool _periodLoading = true;

  Timer? _timer;
  Timer? _periodRefreshTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bootstrapCurrentPeriod();
    _periodRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCurrentPeriodIfChanged(),
    );
  }

  Future<void> _bootstrapCurrentPeriod() async {
    setState(() {
      _periodLoading = true;
      _feedback = null;
    });

    final period = await _service.getCurrentClassPeriod();
    if (!mounted) return;

    setState(() {
      _selectedPeriod = period;
      _periodLoading = false;
      if (period == null) {
        _session = null;
        _timeLeft = Duration.zero;
        _feedback = 'No active class period right now.';
      }
    });

    _listenCurrentSession();
  }

  Future<void> _refreshCurrentPeriodIfChanged() async {
    final period = await _service.getCurrentClassPeriod();
    if (!mounted || period == _selectedPeriod) return;

    setState(() {
      _selectedPeriod = period;
      _session = null;
      _timeLeft = Duration.zero;
      _feedback = period == null ? 'No active class period right now.' : null;
    });

    _listenCurrentSession();
  }

  void _listenCurrentSession() {
    final period = _selectedPeriod;
    _sessionSubscription?.cancel();
    if (period == null || period.isEmpty) {
      _session = null;
      _timeLeft = Duration.zero;
      return;
    }

    _sessionSubscription = _service
        .watchSession(period: period)
        .listen((session) {
          if (!mounted) return;
          setState(() {
            _session = session;
            _syncTimer();
          });
        });
  }

  Future<void> _startAttendance() async {
    final period = _selectedPeriod;
    if (period == null || period.isEmpty) {
      setState(() {
        _feedback = 'No active class period right now.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _feedback = null;
    });

    try {
      final polygon = await _service.getClassroomPolygonForPeriod(period);

      final session = await _service.startOrReuseSession(
        period: period,
        classroomPolygon: polygon,
      );

      setState(() {
        _session = session;
        _feedback = 'Attendance code ready';
        _syncTimer();
      });
    } on AttendanceError catch (e) {
      setState(() {
        _feedback = e.message;
      });
    } catch (_) {
      setState(() {
        _feedback = 'Failed to start attendance session';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _syncTimer() {
    _timer?.cancel();

    final session = _session;
    if (session == null || session.expiresAt == null) {
      _timeLeft = Duration.zero;
      return;
    }

    _timeLeft = session.timeLeft;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;

      final left = session.expiresAt!.difference(DateTime.now());
      if (left.isNegative || left == Duration.zero) {
        _timer?.cancel();
        setState(() {
          _timeLeft = Duration.zero;
        });
        if (session.status == 'active') {
          await _service.markSessionExpired(sessionId: session.id).catchError((_) {});
        }
        return;
      }

      setState(() {
        _timeLeft = left;
      });
    });
  }

  String _durationText(Duration duration) {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _periodRefreshTimer?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final currentPeriod = _selectedPeriod;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Smart Attendance',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Period',
                    style: GoogleFonts.poppins(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: _periodLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Detecting current class period...',
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(
                                Icons.menu_book_rounded,
                                size: 18,
                                color: Color(0xFF8BD4FF),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  currentPeriod ?? 'No active class period',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.more_vert,
                                color: Colors.white.withValues(alpha: 0.8),
                                size: 18,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF61B9E8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: (_loading || _periodLoading || currentPeriod == null)
                          ? null
                          : _startAttendance,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(_loading ? 'Starting...' : 'Start Attendance'),
                        ],
                      ),
                    ),
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _feedback!,
                      style: GoogleFonts.poppins(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      title: 'Code',
                      value: session?.code.isNotEmpty == true ? session!.code : '--',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricTile(
                      title: 'Timer',
                      value: _durationText(_timeLeft),
                      valueColor: _timeLeft.inSeconds <= 60
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricTile(
                      title: 'Status',
                      value: session?.isActive == true ? 'ACTIVE' : 'EXPIRED',
                      valueColor: session?.isActive == true
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (currentPeriod != null)
              _LiveAttendancePanel(
                period: currentPeriod,
                service: _service,
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const _MetricTile({
    required this.title,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _LiveAttendancePanel extends StatelessWidget {
  final String period;
  final SmartAttendanceService service;

  const _LiveAttendancePanel({required this.period, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StudentAttendanceView>>(
      stream: service.watchAttendanceForSession(period: period),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return GlassCard(
            child: Text(
              'Unable to load attendance stream',
              style: GoogleFonts.poppins(color: AppColors.danger),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rows = snapshot.data!;
        final summary = service.buildSummary(rows);
        final present = summary.presentCount;
        final absent = summary.absentCount;

        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Students',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'Present',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'Absent',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Text(
                  'No students found',
                  style: GoogleFonts.poppins(color: AppColors.textSecondary),
                )
              else
                ...rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => service.manualOverride(
                                  studentUid: row.uid,
                                  studentName: row.name,
                                  period: period,
                                  status: 'present',
                                ),
                                child: _StatusCircle(
                                  active: row.status == 'present',
                                  activeColor: const Color(0xFF49D19C),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => service.manualOverride(
                                  studentUid: row.uid,
                                  studentName: row.name,
                                  period: period,
                                  status: 'absent',
                                ),
                                child: _StatusCircle(
                                  active: row.status == 'absent',
                                  activeColor: const Color(0xFFFF8F8F),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total Present: $present',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Total Absent: $absent',
                            textAlign: TextAlign.end,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CountPill(
                            icon: Icons.check_circle,
                            value: present,
                            background: const Color(0xFF65B9E5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CountPill(
                            icon: Icons.cancel,
                            value: absent,
                            background: const Color(0xFFF39CA0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusCircle extends StatelessWidget {
  final bool active;
  final Color activeColor;

  const _StatusCircle({
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
        border: Border.all(
          color: active ? activeColor : Colors.white.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: active
          ? Icon(Icons.check, size: 18, color: activeColor)
          : null,
    );
  }
}

class _CountPill extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color background;

  const _CountPill({
    required this.icon,
    required this.value,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}
