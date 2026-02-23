import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class AdminHomeScreen extends StatelessWidget {
  final Map<String, dynamic> adminData;
  const AdminHomeScreen({super.key, required this.adminData});

  String get _name => adminData['name'] ?? 'Admin';

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
              children: const [
                _StatTile('Total Students', '128', Icons.people_rounded,
                    AppColors.lightBlue),
                _StatTile('Present Today', '112', Icons.how_to_reg_rounded,
                    AppColors.success),
                _StatTile('Low Attendance', '8', Icons.warning_rounded,
                    AppColors.warning),
                _StatTile('Alerts Sent', '14', Icons.notifications_active_rounded,
                    AppColors.danger),
              ],
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 24),

            // Enrolment trend chart
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance Trend (This Week)',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: Colors.white.withValues(alpha: 0.07),
                            strokeWidth: 1,
                          ),
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
                                final i = v.toInt();
                                if (i < 0 || i >= days.length) {
                                  return const SizedBox.shrink();
                                }
                                return Text(days[i],
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
                            spots: const [
                              FlSpot(0, 108),
                              FlSpot(1, 115),
                              FlSpot(2, 110),
                              FlSpot(3, 112),
                              FlSpot(4, 120),
                            ],
                            isCurved: true,
                            color: AppColors.success,
                            barWidth: 3,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, _, _, _) =>
                                  FlDotCirclePainter(
                                radius: 4,
                                color: AppColors.success,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.success.withValues(alpha: 0.12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
            ..._recentAlerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AlertTile(a).animate().fadeIn(delay: 400.ms),
                )),
          ],
        ),
      ),
    );
  }
}

const _recentAlerts = [
  _AlertInfo('Juan Santos — Low Attendance', '65% — Chemistry',
      AppColors.danger),
  _AlertInfo('Maria Cruz — Assignment Pending', 'Math Assignment overdue',
      AppColors.warning),
  _AlertInfo('Pedro Reyes — Absent 3 Days', 'Consecutive absences',
      AppColors.warning),
];

class _AlertInfo {
  final String name;
  final String detail;
  final Color color;
  const _AlertInfo(this.name, this.detail, this.color);
}

class _AlertTile extends StatelessWidget {
  final _AlertInfo a;
  const _AlertTile(this.a);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: a.color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: a.color, size: 10),
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
                Text(a.detail,
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
  const _StatTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
