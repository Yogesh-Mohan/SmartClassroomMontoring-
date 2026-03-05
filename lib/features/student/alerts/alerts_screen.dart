import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../models/student_alert_model.dart';
import '../../../services/tasks_service.dart';
import '../../../utils/date_helpers.dart';

class AlertsScreen extends StatefulWidget {
  final String studentUID;
  final List<String> classCandidates;
  final List<String> studentLookupKeys;
  final ValueChanged<StudentAlert>? onAlertTap;

  const AlertsScreen({
    super.key,
    required this.studentUID,
    required this.classCandidates,
    required this.studentLookupKeys,
    this.onAlertTap,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final TasksService _tasksService = TasksService();
  int _refreshKey = 0;

  void _retry() => setState(() => _refreshKey++);

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
    widget.onAlertTap?.call(alert);
  }

  StudentAlert _toTaskAlert(TaskWithSubmission item) {
    final task = item.task;
    final taskTitle = task.title.trim().isEmpty ? 'Assigned Task' : task.title.trim();
    return StudentAlert(
      id: task.id ?? '${task.title}_${task.createdAt.millisecondsSinceEpoch}',
      type: StudentAlertType.taskAssigned,
      title: taskTitle,
      message: 'Task assigned by admin. Tap to open Tasks.',
      createdAt: task.createdAt,
      isRead: false,
      taskId: task.id,
      cycleKey: null,
    );
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
              child: StreamBuilder<List<TaskWithSubmission>>(
                key: ValueKey(_refreshKey),
                stream: _tasksService.streamStudentAssignedTasks(
                  studentUID: widget.studentUID,
                  classCandidates: widget.classCandidates,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.danger, size: 40),
                          const SizedBox(height: 12),
                          Text('Failed to load alerts',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              snapshot.error.toString(),
                              style: GoogleFonts.poppins(
                                  color: AppColors.textSecondary, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded,
                                color: AppColors.lightBlue),
                            label: Text('Retry',
                                style: GoogleFonts.poppins(
                                    color: AppColors.lightBlue,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                  }

                  final alerts = (snapshot.data ?? const <TaskWithSubmission>[])
                      .map(_toTaskAlert)
                      .where((alert) => DateHelpers.isInCurrentPeriod(alert.createdAt))
                      .toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  if (alerts.isEmpty) {
                    return Center(
                      child: Text(
                        'No task alerts yet',
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
