import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/smart_attendance_service.dart';
import '../../../services/student_count_service.dart';

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
      // Geofence polygon no longer required for attendance
      final session = await _service.startOrReuseSession(
        period: period,
        classroomPolygon: '',
      );

      setState(() {
        _session = session;
        _feedback = session.isClosed
            ? '${session.period} attendance closed'
            : 'Attendance code ready';
        _syncTimer();
      });
    } on AttendanceError catch (e) {
      setState(() {
        _feedback = e.message;
      });
    } on FirebaseException catch (e) {
      setState(() {
        _feedback = e.code == 'permission-denied'
            ? 'Firestore permission denied. Ensure your admin account exists in the admins collection.'
            : 'Firestore error: ${e.message ?? e.code}';
      });
    } catch (e) {
      setState(() {
        _feedback = 'Failed to start attendance session: $e';
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

  Widget _buildLiveCameraCountCard() {
    return StreamBuilder<int>(
      stream: StudentCountService().streamStudentCount(classroomId: 'CR-01'),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final statusColor = count > 0 ? AppColors.success : AppColors.textSecondary;

        return GlassCard(
          child: Row(
            children: [
              Icon(Icons.videocam_rounded, color: statusColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Live Camera Count',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count',
                style: GoogleFonts.poppins(
                  color: statusColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Students',
                style: GoogleFonts.poppins(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
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
    final periodClosed = session?.isClosed == true;
    final currentPeriodLabel = periodClosed && currentPeriod != null
        ? '$currentPeriod (Attendance Closed)'
        : (currentPeriod ?? 'No active class period');

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
            _buildLiveCameraCountCard(),
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
                                  currentPeriodLabel,
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
                          || periodClosed
                          ? null
                          : _startAttendance,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            periodClosed
                                ? 'Attendance Closed'
                                : (_loading ? 'Starting...' : 'Start Attendance'),
                          ),
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
                      value: periodClosed
                          ? 'CLOSED'
                          : (session?.isActive == true ? 'ACTIVE' : 'EXPIRED'),
                      valueColor: periodClosed
                          ? AppColors.warning
                          : (session?.isActive == true
                                ? AppColors.success
                                : AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (currentPeriod != null)
              StreamBuilder<int>(
                stream: StudentCountService().streamStudentCount(classroomId: 'CR-01'),
                builder: (context, countSnapshot) {
                  final liveCameraCount = countSnapshot.data ?? 0;
                  return _LiveAttendancePanel(
                    period: currentPeriod,
                    service: _service,
                    liveCameraCount: liveCameraCount,
                  );
                },
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

class _LiveAttendancePanel extends StatefulWidget {
  final String period;
  final SmartAttendanceService service;
  final int liveCameraCount;

  const _LiveAttendancePanel({
    required this.period,
    required this.service,
    required this.liveCameraCount,
  });

  @override
  State<_LiveAttendancePanel> createState() => _LiveAttendancePanelState();
}

class _LiveAttendancePanelState extends State<_LiveAttendancePanel> {
  final Map<String, String> _draftStatusByUid = <String, String>{};
  bool _submitting = false;

  String _effectiveStatus(StudentAttendanceView row) {
    return _draftStatusByUid[row.uid] ?? row.status;
  }

  void _stageStatus(StudentAttendanceView row, String nextStatus) {
    if (_submitting) return;
    setState(() {
      if (row.status == nextStatus) {
        _draftStatusByUid.remove(row.uid);
      } else {
        _draftStatusByUid[row.uid] = nextStatus;
      }
    });
  }

  Future<void> _submitAttendance(List<StudentAttendanceView> rows) async {
    if (_submitting) return;

    final changed = <String, String>{};
    final names = <String, String>{};

    for (final row in rows) {
      final drafted = _draftStatusByUid[row.uid];
      if (drafted == null || drafted == row.status) continue;
      changed[row.uid] = drafted;
      names[row.uid] = row.name;
    }

    setState(() => _submitting = true);
    try {
      if (changed.isNotEmpty) {
        await widget.service.manualOverrideBatch(
          period: widget.period,
          statusByStudentUid: changed,
          nameByStudentUid: names,
        );
      }

      await widget.service.markPeriodSubmitted(period: widget.period);

      if (!mounted) return;
      setState(() {
        _draftStatusByUid.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance submitted successfully for ${widget.period}',
          ),
        ),
      );
    } on AttendanceError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit attendance')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AttendanceSession?>(
      stream: widget.service.watchSession(period: widget.period),
      builder: (context, sessionSnapshot) {
        final isPeriodClosed = sessionSnapshot.data?.isClosed == true;

        return StreamBuilder<List<StudentAttendanceView>>(
          stream: widget.service.watchAttendanceForSession(period: widget.period),
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
        var present = 0;
        for (final row in rows) {
          if (_effectiveStatus(row) == 'present') {
            present++;
          }
        }
        final currentCameraCount = widget.liveCameraCount;

        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPeriodClosed) ...[
                Text(
                  '${widget.period} attendance closed',
                  style: GoogleFonts.poppins(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
                                onTap: (_submitting || isPeriodClosed)
                                    ? null
                                    : () => _stageStatus(row, 'present'),
                                child: _StatusCircle(
                                  active: _effectiveStatus(row) == 'present',
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
                                onTap: (_submitting || isPeriodClosed)
                                    ? null
                                    : () => _stageStatus(row, 'absent'),
                                child: _StatusCircle(
                                  active: _effectiveStatus(row) == 'absent',
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
                            'Current Students (Camera): $currentCameraCount',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _CountPill(
                      icon: Icons.videocam_rounded,
                      value: currentCameraCount,
                      background: const Color(0xFF65B9E5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF61B9E8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (_submitting || isPeriodClosed)
                      ? null
                      : () => _submitAttendance(rows),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_submitting) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.upload_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(_submitting ? 'Submitting...' : 'Submit Attendance'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
          },
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
