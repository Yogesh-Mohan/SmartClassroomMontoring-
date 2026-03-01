import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  static const _alerts = [
    _Alert(
      type: _AlertType.task,
      'Task Alert (Admin)',
      'New task sent by admin. Please complete and submit your proof.',
      'Now',
    ),
    _Alert(
      type: _AlertType.ruleBroken,
      'Rule Broken Alert',
      'Classroom rule violation detected. Please avoid phone usage during class.',
      'Now',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alerts',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white))
                .animate()
                .fadeIn(),
            const SizedBox(height: 6),
            Text('Notifications & warnings',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textSecondary))
                .animate()
                .fadeIn(delay: 100.ms),
            const SizedBox(height: 24),
            ..._alerts.asMap().entries.map((e) {
              final i = e.key;
              final a = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GlassCard(
                  borderRadius: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: a.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(a.icon, color: a.color, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(a.title,
                                      style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                ),
                                Text(a.time,
                                    style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(a.message,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: 200 + i * 80))
                    .slideX(begin: 0.05, end: 0),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Alert {
  final _AlertType type;
  final String title;
  final String message;
  final String time;

  const _Alert(
    this.title,
    this.message,
    this.time, {
    required this.type,
  });

  Color get color {
    switch (type) {
      case _AlertType.ruleBroken:
        return AppColors.danger;
      case _AlertType.task:
        return AppColors.warning;
    }
  }

  IconData get icon {
    switch (type) {
      case _AlertType.ruleBroken:
        return Icons.warning_rounded;
      case _AlertType.task:
        return Icons.assignment_rounded;
    }
  }
}

enum _AlertType {
  task,
  ruleBroken,
}
