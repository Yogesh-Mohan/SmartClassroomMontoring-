import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

/// AdminAttendanceScreen
///
/// Tab 1 — Attendance : real-time list of all attendance docs, filterable.
/// Tab 2 — Logout Alerts : real-time list of logout_attempts docs;
///          snackbar fires whenever a new early-logout attempt arrives.
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // ── Filters ────────────────────────────────────────────────────────────────
  String _filterBy  = 'date';         // 'date' | 'studentName' | 'regNo'
  final _searchCtrl = TextEditingController();
  String _searchText = '';

  // ── Logout-alert realtime tracking (for snackbar) ───────────────────────
  int _knownAlertCount = -1; // -1 = first load, don't show snackbar yet

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _searchText = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTs(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate().toLocal();
    final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap  •  ${dt.day.toString().padLeft(2,'0')}/'
        '${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilter(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_searchText.isEmpty) return docs;
    return docs.where((doc) {
      final d = doc.data();
      switch (_filterBy) {
        case 'studentName':
          return (d['studentName'] ?? '').toString().toLowerCase()
              .contains(_searchText);
        case 'regNo':
          return (d['regNo'] ?? '').toString().toLowerCase()
              .contains(_searchText);
        case 'date':
        default:
          return (d['date'] ?? '').toString().toLowerCase()
              .contains(_searchText);
      }
    }).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Attendance',
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [AppColors.lightBlue, AppColors.cyan]),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.lightBlue.withValues(alpha: 0.4),
                          blurRadius: 12)
                    ],
                  ),
                  child: const Icon(Icons.event_available_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ).animate().fadeIn(),
          ),

          const SizedBox(height: 12),

          // ── Tabs ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.lightBlue, AppColors.cyan]),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    GoogleFonts.poppins(fontSize: 12),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: const [
                  Tab(text: 'Attendance'),
                  Tab(text: 'Logout Alerts'),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 80.ms),

          const SizedBox(height: 12),

          // ── Filter bar (Attendance tab only) ────────────────────────────
          AnimatedBuilder(
            animation: _tab,
            builder: (_, _) => _tab.index == 0
                ? _FilterBar(
                    filterBy:  _filterBy,
                    ctrl:      _searchCtrl,
                    onChanged: (v) => setState(() {
                      _filterBy  = v;
                      _searchText = _searchCtrl.text.trim().toLowerCase();
                    }),
                  ).animate().fadeIn()
                : const SizedBox.shrink(),
          ),

          // ── Tab views ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _AttendanceTab(
                  applyFilter: _applyFilter,
                  formatTs:    _formatTs,
                ),
                _AlertsTab(
                  formatTs:         _formatTs,
                  onNewAlert:       _onNewAlert,
                  knownAlertCount:  _knownAlertCount,
                  onCountInit:      (c) => _knownAlertCount = c,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onNewAlert(String studentName, String period) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: AppColors.danger,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Early Logout Attempt — $studentName (Period $period)',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String filterBy;
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;

  const _FilterBar({
    required this.filterBy,
    required this.ctrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          // Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: filterBy,
                dropdownColor: const Color(0xFF0D0D2B),
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.white),
                icon: const Icon(Icons.arrow_drop_down,
                    color: AppColors.textSecondary),
                items: const [
                  DropdownMenuItem(
                      value: 'date',
                      child: Text('Date')),
                  DropdownMenuItem(
                      value: 'studentName',
                      child: Text('Name')),
                  DropdownMenuItem(
                      value: 'regNo',
                      child: Text('Reg No')),
                ],
                onChanged: (v) { if (v != null) onChanged(v); },
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Search field
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: ctrl,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textSecondary, size: 18),
                  suffixIcon: ctrl.text.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.clear,
                              color: AppColors.textSecondary, size: 18),
                          onPressed: () => ctrl.clear(),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Attendance
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceTab extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
          List<QueryDocumentSnapshot<Map<String, dynamic>>>)
      applyFilter;
  final String Function(Timestamp?) formatTs;

  const _AttendanceTab({
    required this.applyFilter,
    required this.formatTs,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .orderBy('loginTime', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return _CenteredMsg(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              text: 'Error: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppColors.lightBlue));
        }

        final docs = applyFilter(snap.data?.docs ?? []);

        if (docs.isEmpty) {
          return const _CenteredMsg(
              icon: Icons.event_available_outlined,
              color: AppColors.textSecondary,
              text: 'No attendance records found.');
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d          = docs[i].data();
            final name       = (d['studentName'] ?? '—').toString();
            final regNo      = (d['regNo']       ?? '—').toString();
            final date       = (d['date']        ?? '—').toString();
            final loginTs    = d['loginTime']  as Timestamp?;
            final logoutTs   = d['logoutTime'] as Timestamp?;
            final logoutType = (d['logoutType'] ?? '').toString();
            final isActive   = logoutTs == null;

            return _AttendanceCard(
              name:       name,
              regNo:      regNo,
              date:       date,
              loginTime:  formatTs(loginTs),
              logoutTime: logoutTs != null ? formatTs(logoutTs) : null,
              logoutType: logoutType,
              isActive:   isActive,
              index:      i,
            );
          },
        );
      },
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final String  name, regNo, date, loginTime;
  final String? logoutTime, logoutType;
  final bool    isActive;
  final int     index;

  const _AttendanceCard({
    required this.name,
    required this.regNo,
    required this.date,
    required this.loginTime,
    required this.isActive,
    required this.index,
    this.logoutTime,
    this.logoutType,
  });

  @override
  Widget build(BuildContext context) {
    final badge = isActive
        ? _Badge('Still Active',  AppColors.warning)
        : _Badge('Completed',     AppColors.success);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: name + badge
            Row(
              children: [
                const Icon(Icons.person_rounded,
                    color: AppColors.lightBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                badge,
              ],
            ),

            const SizedBox(height: 10),
            _Row(Icons.badge_rounded, 'Reg No', regNo),
            const SizedBox(height: 6),
            _Row(Icons.calendar_today_rounded, 'Date', date),
            const SizedBox(height: 6),
            _Row(Icons.login_rounded, 'Login', loginTime),
            const SizedBox(height: 6),
            _Row(
              Icons.logout_rounded,
              'Logout',
              logoutTime ?? 'Not Logged Out',
              valueColor: logoutTime == null
                  ? AppColors.warning
                  : AppColors.success,
            ),
            if (logoutType != null && logoutType!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _Row(Icons.info_outline_rounded, 'Type', logoutType!),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 40 * index))
        .slideY(begin: 0.1, end: 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Logout Alerts
// ─────────────────────────────────────────────────────────────────────────────

class _AlertsTab extends StatefulWidget {
  final String Function(Timestamp?) formatTs;
  final void Function(String studentName, String period) onNewAlert;
  final int knownAlertCount;
  final void Function(int) onCountInit;

  const _AlertsTab({
    required this.formatTs,
    required this.onNewAlert,
    required this.knownAlertCount,
    required this.onCountInit,
  });

  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<_AlertsTab> {
  int _localKnown = -1;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('logout_attempts')
          .orderBy('attemptTime', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return _CenteredMsg(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              text: 'Error: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppColors.lightBlue));
        }

        final docs = snap.data?.docs ?? [];

        // Snackbar logic: fire when count increases after first load.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_localKnown == -1) {
            // First load — baseline, no snackbar.
            _localKnown = docs.length;
            widget.onCountInit(docs.length);
            return;
          }
          if (docs.length > _localKnown) {
            // New document(s) arrived.
            final newest = docs.first.data();
            widget.onNewAlert(
              (newest['studentName'] ?? '—').toString(),
              (newest['period']      ?? '—').toString(),
            );
            _localKnown = docs.length;
          }
        });

        if (docs.isEmpty) {
          return const _CenteredMsg(
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.success,
              text: 'No early logout attempts recorded.');
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d    = docs[i].data();
            final type = (d['type'] ?? '').toString();
            final rawPeriod = (d['period'] ?? '').toString().trim();
            final periodDisplay = (rawPeriod.isEmpty ||
                    rawPeriod == '—' ||
                    rawPeriod == 'unknown')
                ? 'Outside Class Hours'
                : rawPeriod;
            return _AlertCard(
              name:        (d['studentName'] ?? '—').toString(),
              regNo:       (d['regNo']       ?? '—').toString(),
              period:      periodDisplay,
              attemptTime: widget.formatTs(d['attemptTime'] as Timestamp?),
              type:        type,
              isEarly:     type == 'early_logout',
              index:       i,
            );
          },
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String name, regNo, period, attemptTime, type;
  final bool   isEarly;
  final int    index;

  const _AlertCard({
    required this.name,
    required this.regNo,
    required this.period,
    required this.attemptTime,
    required this.type,
    required this.isEarly,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEarly
                ? AppColors.danger.withValues(alpha: 0.6)
                : AppColors.warning.withValues(alpha: 0.4),
            width: 1.4,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isEarly
                ? [
                    const Color(0xFFFF3D00).withValues(alpha: 0.18),
                    const Color(0xFF0D0D2B).withValues(alpha: 0.85),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.03),
                  ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEarly
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline_rounded,
                  color: isEarly ? AppColors.danger : AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                _Badge(
                  isEarly ? 'Early Logout' : type,
                  isEarly ? AppColors.danger : AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Row(Icons.badge_rounded, 'Reg No', regNo),
            const SizedBox(height: 6),
            _Row(Icons.class_rounded, 'Period', period),
            const SizedBox(height: 6),
            _Row(Icons.access_time_rounded, 'Attempted', attemptTime),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 40 * index))
        .slideY(begin: 0.1, end: 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    valueColor;

  const _Row(this.icon, this.label, this.value,
      {this.valueColor = AppColors.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text('$label: ',
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: valueColor),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _CenteredMsg extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   text;
  const _CenteredMsg(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
