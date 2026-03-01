import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../models/student_alert_model.dart';
import '../../../services/student_alerts_service.dart';

class AlertsScreen extends StatefulWidget {
  final List<String> studentLookupKeys;
  final ValueChanged<StudentAlert>? onAlertTap;

  const AlertsScreen({
    super.key,
    required this.studentLookupKeys,
    this.onAlertTap,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final StudentAlertsService _alertsService = StudentAlertsService();

  IconData _iconFor(StudentAlertType type) {
    switch (type) {
      case StudentAlertType.ruleSummary:
        return Icons.warning_rounded;
      case StudentAlertType.taskAssigned:
        return Icons.assignment_rounded;
    }
  }

  Color _colorFor(StudentAlertType type) {
    switch (type) {
      case StudentAlertType.ruleSummary:
        return AppColors.danger;
      case StudentAlertType.taskAssigned:
        return AppColors.warning;
    }
  }

  String _timeText(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return DateFormat('dd MMM').format(createdAt);
  }

  Future<void> _handleTap(StudentAlert alert) async {
    if (!alert.isRead) {
      await _alertsService.markAlertRead(alert.id);
    }
    widget.onAlertTap?.call(alert);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<List<StudentAlert>>(
                stream: _alertsService.streamStudentAlerts(
                  studentLookupKeys: widget.studentLookupKeys,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.lightBlue),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load alerts',
                        style: GoogleFonts.poppins(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  final alerts = snapshot.data ?? const <StudentAlert>[];
                  if (alerts.isEmpty) {
                    return Center(
                      child: Text(
                        'No alerts yet',
                        style: GoogleFonts.poppins(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      final alert = alerts[index];
                      final color = _colorFor(alert.type);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: GestureDetector(
                          onTap: () => _handleTap(alert),
                          child: GlassCard(
                            borderRadius: 16,
                            child: Opacity(
                              opacity: alert.isRead ? 0.78 : 1,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(_iconFor(alert.type), color: color, size: 22),
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
                                              child: Text(
                                                alert.title,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _timeText(alert.createdAt),
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          alert.message,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!alert.isRead)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8, top: 4),
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppColors.lightBlue,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(delay: Duration(milliseconds: 180 + index * 60))
                              .slideX(begin: 0.05, end: 0),
                        ),
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
