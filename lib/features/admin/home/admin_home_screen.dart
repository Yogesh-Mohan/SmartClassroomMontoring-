import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/admin_dashboard_service.dart';
import 'admin_metric_detail_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminHomeScreen({super.key, required this.adminData});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  late final AdminDashboardService _dashboardService;

  @override
  void initState() {
    super.initState();
    _dashboardService = AdminDashboardService();
  }

  String get _name => widget.adminData['name'] ?? 'Admin';

  String _monthShort(int m) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[m - 1];
  }

  void _openStudentsList(String title, Stream<List<AdminStudentRow>> stream) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMetricDetailScreen(
          title: title,
          studentsStream: stream,
        ),
      ),
    );
  }

  void _openAlertsList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMetricDetailScreen(
          title: 'Today Alert Events',
          alertsStream: _dashboardService.streamTodayAlertsList(),
        ),
      ),
    );
  }

  Widget _buildCountTile({
    required String label,
    required Stream<int> stream,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.hasData ? '${snapshot.data}' : '...';
        return _StatTile(
          label: label,
          value: value,
          icon: icon,
          color: color,
          onTap: onTap,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      Text('Admin Dashboard',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                      Text(_name,
                          style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.success, Color(0xFF64DD17)],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.4),
                          blurRadius: 12)
                    ],
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Colors.white, size: 24),
                ),
              ],
            ).animate().fadeIn(),

            const SizedBox(height: 24),

            // Stat grid 2×2
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.4,
              children: [
                _buildCountTile(
                  label: 'Total Students',
                  stream: _dashboardService.streamTotalStudentsCount(),
                  icon: Icons.people_rounded,
                  color: AppColors.lightBlue,
                  onTap: () => _openStudentsList(
                    'Total Students',
                    _dashboardService.streamTotalStudentsList(),
                  ),
                ),
                _buildCountTile(
                  label: 'Present Today',
                  stream: _dashboardService.streamPresentTodayCount(),
                  icon: Icons.how_to_reg_rounded,
                  color: AppColors.success,
                  onTap: () => _openStudentsList(
                    'Present Today Students',
                    _dashboardService.streamPresentTodayList(),
                  ),
                ),
                _buildCountTile(
                  label: 'Not Logged In',
                  stream: _dashboardService.streamNotLoggedInTodayCount(),
                  icon: Icons.person_off_rounded,
                  color: AppColors.warning,
                  onTap: () => _openStudentsList(
                    'Not Logged In Today',
                    _dashboardService.streamNotLoggedInTodayList(),
                  ),
                ),
                _buildCountTile(
                  label: 'Today Alerts',
                  stream: _dashboardService.streamTodayAlertsCount(),
                  icon: Icons.notifications_active_rounded,
                  color: AppColors.danger,
                  onTap: _openAlertsList,
                ),
              ],
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 24),

            // Weekly violations bar chart
            StreamBuilder<List<AdminDailyViolation>>(
              stream: _dashboardService.streamWeeklyViolationChart(),
              builder: (context, snapshot) {
                final days = snapshot.data ?? [];
                final maxY = days.isEmpty
                    ? 1.0
                    : days
                            .map((d) => d.count)
                            .reduce((a, b) => a > b ? a : b)
                            .toDouble() +
                        1;
                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phone Violations (Last 7 Days)',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Date · Top violating student shown',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: days.isEmpty
                            ? Center(
                                child: Text('No data',
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: AppColors.textSecondary)),
                              )
                            : BarChart(
                                BarChartData(
                                  maxY: maxY,
                                  barGroups: days.asMap().entries.map((e) {
                                    final hasViolation = e.value.count > 0;
                                    return BarChartGroupData(
                                      x: e.key,
                                      barRods: [
                                        BarChartRodData(
                                          toY: e.value.count.toDouble(),
                                          color: hasViolation
                                              ? AppColors.danger
                                              : Colors.white
                                                  .withValues(alpha: 0.1),
                                          width: 26,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(6)),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                  titlesData: FlTitlesData(
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 46,
                                        getTitlesWidget: (v, _) {
                                          final i = v.toInt();
                                          if (i < 0 || i >= days.length) {
                                            return const SizedBox.shrink();
                                          }
                                          final d = days[i].date;
                                          final dateStr =
                                              '${d.day} ${_monthShort(d.month)}';
                                          final name = days[i].topName;
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(dateStr,
                                                    style: GoogleFonts.poppins(
                                                        fontSize: 9,
                                                        color: AppColors
                                                            .textSecondary)),
                                                Text(
                                                  name.isEmpty
                                                      ? '—'
                                                      : (name.length > 6
                                                          ? '${name.substring(0, 6)}..'
                                                          : name),
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: name.isEmpty
                                                          ? AppColors
                                                              .textSecondary
                                                          : AppColors.danger),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    leftTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                  ),
                                  gridData: const FlGridData(show: false),
                                  borderData: FlBorderData(show: false),
                                  barTouchData: BarTouchData(
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipColor: (_) => Colors.black87,
                                      getTooltipItem: (group, _, rod, _) {
                                        final d = days[group.x];
                                        final count = rod.toY.toInt();
                                        return BarTooltipItem(
                                          count == 0
                                              ? 'No violations'
                                              : '${d.topName}\n$count violation${count == 1 ? '' : 's'}',
                                          GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: Colors.white),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1, end: 0),

            const SizedBox(height: 20),

            // Recent alerts
            Text('Recent Alerts',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white))
                .animate()
                .fadeIn(delay: 350.ms),
            const SizedBox(height: 12),
            StreamBuilder<List<AdminAlertRow>>(
              stream: _dashboardService.streamRecentUniqueAlerts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          color: AppColors.danger, strokeWidth: 2),
                    ),
                  );
                }
                final alerts = snapshot.data ?? [];
                if (alerts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No alerts today.',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: alerts
                      .map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AlertTile(a).animate().fadeIn(delay: 400.ms),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


class _AlertTile extends StatelessWidget {
  final AdminAlertRow a;
  const _AlertTile(this.a);

  String _timeLabel() {
    final dt = a.timestamp.toLocal();
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: AppColors.danger, size: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white)),
                Text('${a.period}  •  ${_timeLabel()}',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
