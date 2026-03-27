import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/monitor_service.dart';

/// LiveMonitoringScreen — Admin real-time view of student phone activity.
///
/// Shows a LIVE counting timer (1, 2, 3…) for each student currently
/// using their phone during class. Timer ticks every second locally
/// and syncs with Firestore data every 3 seconds.
///
/// Also has a "Notify Class" FAB — admin can type a message and
/// push it to ALL present students instantly.
class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  String _search = '';
  String _statusFilter = 'all'; // all | online | offline

  // Admin monitoring master switch state
  bool _monitoringEnabled = true;
  bool _togglingMonitoring = false;
  StreamSubscription<DocumentSnapshot>? _monitoringSettingsStream;

  // Local timer state — key: studentUID, value: local screen seconds
  final Map<String, int> _localTimers = {};
  final Map<String, int> _lastFirestoreScreenTime = {};
  final Map<String, DateTime> _lastFirestoreUpdate = {};
  Timer? _tickTimer;

  // Cached streams to prevent re-subscription loops
  late Stream<QuerySnapshot> _liveStream;
  late Stream<Set<String>> _attendanceStream;
  late Stream<QuerySnapshot> _studentsStream;

  String _todayDateKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${y}_${m}_$d';
  }

  String _effectiveStatus(
    Map<String, dynamic> data, {
    required bool isPresent,
  }) {
    final rawStatus = (data['status'] ?? 'offline').toString();
    bool actuallyPresent = isPresent;

    // Fallback: If not in attendance list, but live_monitoring updated recently (< 2 min), treat as present
    if (!actuallyPresent) {
      final lastParam = data['lastUpdated'];
      if (lastParam is Timestamp) {
        final lastUpdated = lastParam.toDate();
        final diff = DateTime.now().difference(lastUpdated);
        if (diff.inSeconds.abs() < 120) {
          actuallyPresent = true;
        }
      }
    }

    if (!actuallyPresent) return 'offline';

    if (rawStatus == 'active' ||
        rawStatus == 'idle' ||
        rawStatus == 'offline') {
      return rawStatus;
    }
    return 'offline';
  }

  bool _isInteractiveUsage(
    Map<String, dynamic> data, {
    required bool isPresent,
  }) {
    final status = _effectiveStatus(data, isPresent: isPresent);
    final currentApp = (data['currentApp'] ?? '').toString().trim();
    final screenTime = (data['screenTime'] as num?)?.toInt() ?? 0;
    return status == 'active' && currentApp.isNotEmpty && screenTime > 0;
  }

  bool _isOnline(
    Map<String, dynamic> data, {
    required bool isPresent,
  }) {
    if (isPresent) return true;
    final lastParam = data['lastUpdated'];
    if (lastParam is Timestamp) {
      final diff = DateTime.now().difference(lastParam.toDate()).inSeconds.abs();
      return diff < 120;
    }
    return false;
  }

  String _attendanceUid(String docId, Map<String, dynamic> data) {
    final direct =
        (data['studentUID'] ?? data['studentUid'] ?? data['uid'] ?? '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;

    final normalizedDocId = docId.trim();
    final suffixPattern = RegExp(r'_[0-9]{4}_[0-9]{2}_[0-9]{2}$');
    if (suffixPattern.hasMatch(normalizedDocId) && normalizedDocId.length > 11) {
      return normalizedDocId.substring(0, normalizedDocId.length - 11);
    }
    return normalizedDocId;
  }

  @override
  void initState() {
    super.initState();

    // Cache streams once to avoid massive read loops
    _liveStream = FirebaseFirestore.instance
        .collection('live_monitoring')
        .orderBy('lastUpdated', descending: true)
        .snapshots();

    _studentsStream = FirebaseFirestore.instance.collection('students').snapshots();

    _attendanceStream = FirebaseFirestore.instance
        .collection('attendance')
        .where('date', isEqualTo: _todayDateKey())
        .snapshots()
        .map((snap) {
          final present = <String>{};
          for (final doc in snap.docs) {
            final data = doc.data();
            if (data['logoutTime'] != null) continue;
            final uid = _attendanceUid(doc.id, data);
            if (uid.isNotEmpty) present.add(uid);
          }
          return present;
        });

    // Stream admin monitoring master switch state from Firestore
    _monitoringSettingsStream = FirebaseFirestore.instance
        .collection('monitoring_settings')
        .doc('global')
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          final enabled = (doc.data()?['monitoringEnabled'] as bool?) ?? true;
          if (enabled != _monitoringEnabled) {
            setState(() => _monitoringEnabled = enabled);
          }
        });

    // Tick every 1 second to increment local timers
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      bool changed = false;
      for (final uid in _localTimers.keys.toList()) {
        final baseTime = _lastFirestoreScreenTime[uid] ?? 0;
        final lastUpdate = _lastFirestoreUpdate[uid];
        if (lastUpdate != null && baseTime > 0) {
          final elapsed = DateTime.now().difference(lastUpdate).inSeconds;
          final newTime = baseTime + elapsed;
          if (_localTimers[uid] != newTime) {
            _localTimers[uid] = newTime;
            changed = true;
          }
        }
      }
      if (changed) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _monitoringSettingsStream?.cancel();
    super.dispose();
  }

  // ── Admin Toggle ─────────────────────────────────────────────────────────

  Future<void> _toggleMonitoring(bool enable) async {
    if (_togglingMonitoring) return;

    // If turning OFF → show confirmation dialog first
    if (!enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black54,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0D1B3E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          title: Row(
            children: [
              Icon(
                Icons.pause_circle_outline_rounded,
                color: AppColors.warning,
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                'Pause Monitoring?',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          content: Text(
            'Students will be able to use their phones freely.\n\nNo violations will be recorded while monitoring is paused.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: AppColors.textSecondary),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Pause Monitoring',
                  style: GoogleFonts.poppins(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _togglingMonitoring = true);
    try {
      await ScreenMonitorService().setAdminMonitoring(enable);
      setState(() => _monitoringEnabled = enable);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update monitoring state: $e',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingMonitoring = false);
    }
  }

  /// The monitoring master switch banner widget.
  Widget _buildMonitoringToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _monitoringEnabled
              ? AppColors.success.withValues(alpha: 0.12)
              : AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _monitoringEnabled
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.danger.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                _monitoringEnabled
                    ? Icons.security_rounded
                    : Icons.security_update_warning_rounded,
                key: ValueKey(_monitoringEnabled),
                color: _monitoringEnabled
                    ? AppColors.success
                    : AppColors.danger,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _monitoringEnabled
                        ? 'Monitoring ACTIVE'
                        : 'Monitoring PAUSED',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _monitoringEnabled
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                  Text(
                    _monitoringEnabled
                        ? 'Violations will be recorded if usage > 20s'
                        : 'Students can use phones freely — no violations',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _togglingMonitoring
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.lightBlue,
                    ),
                  )
                : Switch.adaptive(
                    value: _monitoringEnabled,
                    onChanged: _toggleMonitoring,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.success,
                    inactiveThumbColor: AppColors.danger,
                    inactiveTrackColor: AppColors.danger.withValues(alpha: 0.3),
                  ),
          ],
        ),
      ).animate().fadeIn(delay: 80.ms),
    );
  }

  /// Sync local timers from fresh Firestore snapshot.
  void _syncTimers(List<QueryDocumentSnapshot> docs, Set<String> presentUids) {
    final docIds = docs.map((d) => d.id).toSet();

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = doc.id;
      final firestoreTime = (data['screenTime'] as num?)?.toInt() ?? 0;
      final interactive = _isInteractiveUsage(
        data,
        isPresent: presentUids.contains(uid),
      );

      // Tick timer only when the student is truly in interactive phone use.
      if (interactive && firestoreTime > 0) {
        final lastBase = _lastFirestoreScreenTime[uid];

        // Only reset local timer anchor when Firestore value actually changes.
        // Otherwise keep counting locally each second until the next backend update.
        if (lastBase == null || firestoreTime != lastBase) {
          _lastFirestoreScreenTime[uid] = firestoreTime;
          _lastFirestoreUpdate[uid] = DateTime.now();
          _localTimers[uid] = firestoreTime;
        } else {
          _localTimers.putIfAbsent(uid, () => firestoreTime);
        }
      } else {
        _localTimers[uid] = 0;
        _lastFirestoreScreenTime[uid] = 0;
        _lastFirestoreUpdate.remove(uid);
      }
    }

    // Remove stale timer entries for docs no longer present in snapshot.
    _localTimers.removeWhere((uid, _) => !docIds.contains(uid));
    _lastFirestoreScreenTime.removeWhere((uid, _) => !docIds.contains(uid));
    _lastFirestoreUpdate.removeWhere((uid, _) => !docIds.contains(uid));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Live Monitoring',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.success.withValues(
                                      alpha: 0.6,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .fade(begin: 0.4, end: 1, duration: 1200.ms),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ).animate().fadeIn(),
            ),
            const SizedBox(height: 14),

            // ── Admin Master Switch ──────────────────────────────────────
            _buildMonitoringToggle(),
            const SizedBox(height: 12),

            // ── Search bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: TextField(
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or register number...',
                    hintStyle: GoogleFonts.poppins(
                      color: AppColors.textSecondary,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 100.ms),
            ),
            const SizedBox(height: 10),

            // ── Filter chips ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _statusFilter == 'all',
                    onTap: () => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Online',
                    selected: _statusFilter == 'online',
                    color: AppColors.success,
                    onTap: () => setState(() => _statusFilter = 'online'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Offline',
                    selected: _statusFilter == 'offline',
                    color: AppColors.warning,
                    onTap: () => setState(() => _statusFilter = 'offline'),
                  ),
                ],
              ).animate().fadeIn(delay: 150.ms),
            ),
            const SizedBox(height: 12),

            // ── Live student list ──────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _liveStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.success,
                        strokeWidth: 2,
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.monitor_heart_outlined,
                            size: 56,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No students being monitored',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Data will appear when students log in',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return StreamBuilder<Set<String>>(
                    stream: _attendanceStream,
                    builder: (context, presentSnapshot) {
                      final presentUids = presentSnapshot.data ?? <String>{};
                      final liveDocs = snapshot.data!.docs;
                      _syncTimers(liveDocs, presentUids);

                      return StreamBuilder<QuerySnapshot>(
                        stream: _studentsStream,
                        builder: (context, studentsSnapshot) {
                          final liveByUid = <String, Map<String, dynamic>>{};
                          for (final doc in liveDocs) {
                            liveByUid[doc.id] = Map<String, dynamic>.from(
                              doc.data() as Map<String, dynamic>,
                            );
                          }

                          final mergedEntries = <Map<String, dynamic>>[];
                          liveByUid.forEach((uid, data) {
                            mergedEntries.add({'uid': uid, 'data': data});
                          });

                          if (studentsSnapshot.hasData) {
                            for (final studentDoc
                                in studentsSnapshot.data!.docs) {
                              final student =
                                  studentDoc.data() as Map<String, dynamic>;
                              final uid = (student['uid'] ?? studentDoc.id)
                                  .toString()
                                  .trim();
                              if (uid.isEmpty) continue;

                              final alreadyInLive = liveByUid.containsKey(uid);
                              final isPresent = presentUids.contains(uid);
                              if (alreadyInLive || isPresent) continue;

                              mergedEntries.add({
                                'uid': uid,
                                'data': {
                                  'studentName':
                                      (student['name'] ??
                                              student['studentName'] ??
                                              'Unknown')
                                          .toString(),
                                  'regNo':
                                      (student['regNo'] ??
                                              student['registrationNumber'] ??
                                              student['studentId'] ??
                                              student['rollNo'] ??
                                              '—')
                                          .toString(),
                                  'currentPeriod': 'Not logged in',
                                  'currentApp': '',
                                  'status': 'offline',
                                },
                              });
                            }
                          }

                          final filtered = mergedEntries.where((entry) {
                            final uid = (entry['uid'] ?? '').toString();
                            final data = entry['data'] as Map<String, dynamic>;
                            final name = (data['studentName'] ?? '')
                                .toString()
                                .toLowerCase();
                            final isOnline = _isOnline(
                              data,
                              isPresent: presentUids.contains(uid),
                            );
                            final matchesSearch =
                                _search.isEmpty ||
                                name.contains(_search.toLowerCase());
                            final matchesFilter = _statusFilter == 'all'
                                ? true
                                : _statusFilter == 'online'
                                ? isOnline
                                : !isOnline;
                            return matchesSearch && matchesFilter;
                          }).toList();

                          final onlineCount = mergedEntries.where((entry) {
                            final uid = (entry['uid'] ?? '').toString();
                            final data = entry['data'] as Map<String, dynamic>;
                            return _isOnline(
                              data,
                              isPresent: presentUids.contains(uid),
                            );
                          }).length;

                          final offlineCount = mergedEntries.length - onlineCount;

                          if (filtered.isEmpty) {
                            return Center(
                              child: Text(
                                'No matching students',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          }

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                            children: [
                              Row(
                                children: [
                                  _SummaryChip(
                                    count: onlineCount,
                                    label: 'Online',
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(width: 10),
                                  _SummaryChip(
                                    count: offlineCount,
                                    label: 'Offline',
                                    color: AppColors.warning,
                                  ),
                                ],
                              ).animate().fadeIn(delay: 200.ms),
                              const SizedBox(height: 14),
                              ...filtered.map((entry) {
                                final uid = (entry['uid'] ?? '').toString();
                                final data =
                                    entry['data'] as Map<String, dynamic>;
                                final isOnline = _isOnline(
                                  data,
                                  isPresent: presentUids.contains(uid),
                                );
                                final interactive = _isInteractiveUsage(
                                  data,
                                  isPresent: presentUids.contains(uid),
                                );
                                final tileData = Map<String, dynamic>.from(data)
                                  ..['status'] = interactive
                                      ? 'active'
                                      : isOnline
                                      ? 'idle'
                                      : 'offline';
                                final liveScreenTime =
                                    interactive ? (_localTimers[uid] ?? 0) : 0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _LiveStudentTile(
                                    data: tileData,
                                    liveScreenTime: liveScreenTime,
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Supporting Widgets ─────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color = AppColors.lightBlue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _SummaryChip({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveStudentTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final int liveScreenTime;

  const _LiveStudentTile({required this.data, required this.liveScreenTime});

  String get _name => (data['studentName'] ?? 'Unknown').toString();
  String get _status => (data['status'] ?? 'offline').toString();

  Color get _statusColor {
    switch (_status) {
      case 'active':
        return AppColors.success;
      case 'idle':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case 'active':
        return Icons.phone_android_rounded;
      case 'idle':
        return Icons.phone_paused_rounded;
      default:
        return Icons.phone_disabled_rounded;
    }
  }

  bool get _isViolation => _status == 'active' && liveScreenTime >= 20;
  bool get _isTimerActive => _status == 'active' && liveScreenTime > 0;

  String _formatTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0
        ? '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isViolation
                ? AppColors.danger.withValues(alpha: 0.5)
                : _isTimerActive
                ? AppColors.warning.withValues(alpha: 0.4)
                : _statusColor.withValues(alpha: 0.25),
            width: _isViolation ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusColor.withValues(alpha: 0.15),
                  ),
                  child: Icon(_statusIcon, color: _statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Live timer badge
                if (_isTimerActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isViolation
                          ? AppColors.danger.withValues(alpha: 0.2)
                          : AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isViolation
                            ? AppColors.danger.withValues(alpha: 0.5)
                            : AppColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          size: 16,
                          color: _isViolation
                              ? AppColors.danger
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(liveScreenTime),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _isViolation
                                ? AppColors.danger
                                : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            // Progress bar (only when timer active)
            if (_isTimerActive) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Phone Usage',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${_formatTime(liveScreenTime)} / 20s',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _isViolation
                          ? AppColors.danger
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (liveScreenTime / 20).clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: _isViolation
                      ? AppColors.danger
                      : liveScreenTime >= 15
                      ? AppColors.warning
                      : AppColors.success,
                  minHeight: 6,
                ),
              ),
            ],
            // Violation warning
            if (_isViolation) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '⚠ VIOLATION — Phone usage exceeded 20s!',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _StudentDetailSheet(data: data, liveScreenTime: liveScreenTime),
    );
  }
}

class _StudentDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final int liveScreenTime;
  const _StudentDetailSheet({required this.data, required this.liveScreenTime});

  @override
  Widget build(BuildContext context) {
    final name = (data['studentName'] ?? 'Unknown').toString();
    final status = (data['status'] ?? 'offline').toString();
    final isViolation = status == 'active' && liveScreenTime >= 20;

    final statusColor = status == 'active'
        ? AppColors.success
        : status == 'idle'
        ? AppColors.warning
        : AppColors.textSecondary;

    String lastUpdatedStr = '—';
    final ts = data['lastUpdated'];
    if (ts is Timestamp) {
      final dt = ts.toDate().toLocal();
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      lastUpdatedStr = '$h:$m:$s $ap';
    }

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
            margin: const EdgeInsets.only(bottom: 20),
          ),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withValues(alpha: 0.2),
            ),
            child: Icon(Icons.person_rounded, size: 36, color: statusColor),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            status == 'offline' ? 'Offline' : 'Online',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          // Big live timer
          if (liveScreenTime > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: isViolation
                    ? AppColors.danger.withValues(alpha: 0.15)
                    : AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isViolation
                      ? AppColors.danger.withValues(alpha: 0.4)
                      : AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.timer_rounded,
                    size: 28,
                    color: isViolation ? AppColors.danger : AppColors.warning,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${liveScreenTime}s',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: isViolation ? AppColors.danger : AppColors.warning,
                    ),
                  ),
                  Text(
                    'Screen Time',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 20),
          _DetailRow('Last Updated', lastUpdatedStr, AppColors.textSecondary),
          if (isViolation) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phone usage exceeded 20s threshold!\nViolation has been recorded.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _DetailRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
