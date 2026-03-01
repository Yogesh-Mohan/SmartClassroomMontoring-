import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/cloudinary_upload_service.dart';
import '../../../services/tasks_service.dart';
import '../../../models/task_model.dart';

class TasksScreen extends StatefulWidget {
  final String studentUID;
  final List<String> classCandidates;
  final List<String> studentLookupKeys;  const TasksScreen({
    super.key,
    required this.studentUID,
    required this.classCandidates,
    this.studentLookupKeys = const [],
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TasksService _tasksService = TasksService();
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;
  late Stream<List<TaskWithSubmission>> _assignedTasksStream;

  @override
  void initState() {
    super.initState();
    _assignedTasksStream = _buildAssignedTasksStream();
  }

  @override
  void didUpdateWidget(covariant TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentUID != widget.studentUID ||
        !_sameClassCandidates(oldWidget.classCandidates, widget.classCandidates) ||
        !_sameClassCandidates(oldWidget.studentLookupKeys, widget.studentLookupKeys)) {
      _assignedTasksStream = _buildAssignedTasksStream();
    }
  }

  String get _effectiveStudentUid {
    final providedUid = widget.studentUID.trim();
    if (providedUid.isNotEmpty) {
      return providedUid;
    }
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.trim().isNotEmpty) {
      return authUid.trim();
    }
    return '';
  }

  Stream<List<TaskWithSubmission>> _buildAssignedTasksStream() {
    return _tasksService.streamStudentAssignedTasks(
      studentUID: _effectiveStudentUid,
      classCandidates: widget.classCandidates,
      studentLookupKeys: widget.studentLookupKeys,
    );
  }

  bool _sameClassCandidates(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _isCloudinaryActive => CloudinaryUploadService.isConfigured;

  Future<void> _pickAndSubmitProof(TaskWithSubmission item) async {
    final status = item.status;
    final attempts = item.submission?.attemptCount ?? 0;
    final taskId = item.task.id;
    if (taskId == null || taskId.trim().isEmpty) {
      _showSnack('Invalid task data. Please refresh and try again.', isError: true);
      return;
    }
    if (status == TaskSubmissionStatus.pending) {
      _showSnack('Already submitted. Wait for admin review.', isError: true);
      return;
    }
    if (status == TaskSubmissionStatus.accepted) {
      _showSnack('Task already accepted.', isError: true);
      return;
    }
    if (attempts >= 3) {
      _showSnack('Proof submission limit reached (3 attempts).', isError: true);
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _uploading = true);
    try {
      await _tasksService.submitTaskProof(
        taskId: taskId,
        studentUID: _effectiveStudentUid,
        imageFile: File(picked.path),
        maxAttempts: 3,
      );
      _showSnack('Proof uploaded. Waiting for admin approval.');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientStart,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppGradients.blueGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Assigned Tasks',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isCloudinaryActive
                          ? AppColors.success.withValues(alpha: 0.18)
                          : AppColors.warning.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isCloudinaryActive
                            ? AppColors.success.withValues(alpha: 0.6)
                            : AppColors.warning.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      _isCloudinaryActive ? 'Cloudinary Active' : 'Firebase Fallback',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _isCloudinaryActive ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(),
            ),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: LinearProgressIndicator(color: AppColors.lightBlue),
              ),
            Expanded(
              child: StreamBuilder<List<TaskWithSubmission>>(
                stream: _assignedTasksStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.lightBlue),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Failed to load tasks\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }

                  final items = snapshot.data ?? [];
                  return Column(
                    children: [
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text(
                                  'No teacher tasks assigned.',
                                  style: GoogleFonts.poppins(color: AppColors.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _TaskAssignmentTile(
                                      item: item,
                                      onUploadProof: () => _pickAndSubmitProof(item),
                                    ).animate().fadeIn(delay: (index * 60).ms),
                                  );
                                },
                              ),
                      ),
                    ],
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

class _TaskAssignmentTile extends StatelessWidget {
  final TaskWithSubmission item;
  final VoidCallback onUploadProof;

  const _TaskAssignmentTile({required this.item, required this.onUploadProof});

  Color _statusColor(TaskSubmissionStatus status) {
    switch (status) {
      case TaskSubmissionStatus.pending:
        return AppColors.warning;
      case TaskSubmissionStatus.accepted:
        return AppColors.success;
      case TaskSubmissionStatus.rejected:
        return AppColors.danger;
      case TaskSubmissionStatus.notSubmitted:
        return AppColors.info;
    }
  }

  String _statusLabel(TaskSubmissionStatus status) {
    switch (status) {
      case TaskSubmissionStatus.pending:
        return 'Pending Review';
      case TaskSubmissionStatus.accepted:
        return 'Accepted';
      case TaskSubmissionStatus.rejected:
        return 'Rejected';
      case TaskSubmissionStatus.notSubmitted:
        return 'Not Submitted';
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final submission = item.submission;
    final status = item.status;
    final color = _statusColor(status);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _statusLabel(status),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            task.description,
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Due: ${DateFormat('dd MMM yyyy').format(task.dueDate)}',
            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (submission != null) ...[
            const SizedBox(height: 8),
            Text(
              'Attempts: ${submission.attemptCount}/3',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (submission.reviewComment.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Review: ${submission.reviewComment}',
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
              ),
            ]
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (status == TaskSubmissionStatus.pending ||
                      status == TaskSubmissionStatus.accepted ||
                      (submission?.attemptCount ?? 0) >= 3)
                  ? null
                  : onUploadProof,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.lightBlue,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
              label: Text(
                status == TaskSubmissionStatus.rejected
                    ? 'Re-upload Proof'
                    : 'Upload Proof',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
