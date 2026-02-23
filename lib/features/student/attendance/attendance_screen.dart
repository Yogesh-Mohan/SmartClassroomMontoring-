import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class AttendanceScreen extends StatelessWidget {
  final Map<String, dynamic> studentData;
  const AttendanceScreen({super.key, required this.studentData});

  static const _subjects = [
    _SubjectAtt('Mathematics', 28, 32, AppColors.lightBlue),
    _SubjectAtt('Physics', 24, 30, AppColors.warning),
    _SubjectAtt('English', 30, 32, AppColors.success),
    _SubjectAtt('Chemistry', 20, 28, AppColors.danger),
    _SubjectAtt('Comp. Science', 26, 28, AppColors.info),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white))
                .animate()
                .fadeIn(),

            const SizedBox(height: 6),
            Text('Current semester overview',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textSecondary))
                .animate()
                .fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // Overall gauge card
            GlassCard(
              child: Column(
                children: [
                  Text('Overall Attendance',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 48,
                        sections: [
                          PieChartSectionData(
                            value: 87,
                            color: AppColors.success,
                            title: '87%',
                            radius: 32,
                            titleStyle: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          PieChartSectionData(
                            value: 13,
                            color: Colors.white.withValues(alpha: 0.1),
                            title: '',
                            radius: 28,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Legend(AppColors.success, 'Present'),
                      const SizedBox(width: 20),
                      _Legend(
                          Colors.white.withValues(alpha: 0.2), 'Absent'),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

            const SizedBox(height: 24),

            Text('By Subject',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white))
                .animate()
                .fadeIn(delay: 300.ms),
            const SizedBox(height: 12),

            ..._subjects.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SubjectBar(s).animate().fadeIn(
                    delay: Duration(milliseconds: 350 + i * 60)),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SubjectAtt {
  final String name;
  final int attended;
  final int total;
  final Color color;
  const _SubjectAtt(this.name, this.attended, this.total, this.color);
  double get pct => total == 0 ? 0 : attended / total;
}

class _SubjectBar extends StatelessWidget {
  final _SubjectAtt s;
  const _SubjectBar(this.s);

  @override
  Widget build(BuildContext context) {
    final pct = (s.pct * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.name,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white)),
              Text('$pct% (${s.attended}/${s.total})',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.pct,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(s.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
