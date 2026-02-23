import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';

class StudentHomeScreen extends StatelessWidget {
  final Map<String, dynamic> studentData;
  const StudentHomeScreen({super.key, required this.studentData});

  String get _name => studentData['name'] ?? 'Student';
  String get _studentId => studentData['studentId'] ?? '—';

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

            // Stats row
            Row(
              children: [
                _StatCard('Attendance', '87%', Icons.event_available_rounded,
                    AppColors.success),
                const SizedBox(width: 14),
                _StatCard('GPA', '3.6', Icons.school_rounded,
                    AppColors.lightBlue),
                const SizedBox(width: 14),
                _StatCard('Alerts', '2', Icons.notifications_rounded,
                    AppColors.warning),
              ],
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 24),

            // Performance chart
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly Performance',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 140,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
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
                                const days = ['M', 'T', 'W', 'T', 'F'];
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
                              FlSpot(0, 70),
                              FlSpot(1, 85),
                              FlSpot(2, 78),
                              FlSpot(3, 90),
                              FlSpot(4, 88),
                            ],
                            isCurved: true,
                            color: AppColors.lightBlue,
                            barWidth: 3,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, _, _, _) =>
                                  FlDotCirclePainter(
                                radius: 4,
                                color: AppColors.lightBlue,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.lightBlue.withValues(alpha: 0.15),
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

            // Today's classes
            Text("Today's Schedule",
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white))
                .animate().fadeIn(delay: 350.ms),
            const SizedBox(height: 12),
            ..._todayClasses.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ClassTile(c).animate().fadeIn(delay: 400.ms),
                )),
          ],
        ),
      ),
    );
  }
}

const _todayClasses = [
  _ClassInfo('Mathematics', '09:00 – 10:30', 'Room 101', AppColors.lightBlue),
  _ClassInfo('Physics', '11:00 – 12:30', 'Lab 1', AppColors.warning),
  _ClassInfo('English', '14:00 – 15:30', 'Room 202', AppColors.success),
];

class _ClassInfo {
  final String subject;
  final String time;
  final String room;
  final Color color;
  const _ClassInfo(this.subject, this.time, this.room, this.color);
}

class _ClassTile extends StatelessWidget {
  final _ClassInfo info;
  const _ClassTile(this.info);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: info.color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 40, color: info.color,
              margin: const EdgeInsets.only(right: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.subject,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(info.time,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(info.room,
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
