import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../models/task_model.dart';
import '../../../services/tasks_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final TasksService _tasksService = TasksService();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _selectedClass;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  bool _sendAll = true;
  bool _submitting = false;

  List<String> _classIds = [];
  List<Map<String, dynamic>> _studentsInClass = [];
  final Set<String> _selectedStudents = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadClasses();
  }

  @override
  void dispose() {
    _tab.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final classes = await _tasksService.getAvailableClassIdsFromTimetable();
    if (!mounted) return;
    setState(() {
      _classIds = classes;
      if (_classIds.isNotEmpty) {
        _selectedClass ??= _classIds.first;
      }
    });
    if (_selectedClass != null) {
      await _loadStudentsForClass(_selectedClass!);
    }
  }

  Future<void> _loadStudentsForClass(String classId) async {
    final students = await _tasksService.getStudentsForClass(classId);
    if (!mounted) return;
    setState(() {
      _studentsInClass = students;
      _selectedStudents.clear();
    });
  }

  Future<void> _createTask() async {
    if (_selectedClass == null) {
      _showSnack('Select class first', isError: true);
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('Enter task title', isError: true);
      return;
    }
    if (!_sendAll && _selectedStudents.isEmpty) {
      _showSnack('Select at least one student', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _tasksService.createTaskAssignment(
        createdByUID: FirebaseAuth.instance.currentUser?.uid ?? '',
        targetClassId: _selectedClass!,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        dueDate: _dueDate,
        audienceType:
            _sendAll ? TaskAudienceType.allInClass : TaskAudienceType.selectedStudents,
        assigneeUIDs: _selectedStudents.toList(),
      );
      _showSnack('Task sent successfully');
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _sendAll = true;
        _selectedStudents.clear();
      });
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _review(
    PendingSubmissionItem item, {
    required bool accepted,
  }) async {
    final commentCtrl = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(accepted ? 'Accept Proof' : 'Reject Proof'),
        content: TextField(
          controller: commentCtrl,
          decoration: const InputDecoration(
            hintText: 'Optional comment',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, commentCtrl.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (comment == null) return;

    try {
      final reviewer = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _tasksService.reviewSubmission(
        taskId: item.taskId,
        studentUID: item.submission.studentUID,
        accepted: accepted,
        reviewedByUID: reviewer,
        comment: comment,
      );

      final token = await _getStudentFcmToken(item.submission.studentUID);
      if (token != null && token.isNotEmpty) {
        await _sendPushNotification(
          token: token,
          title: accepted ? '✅ Task Approved' : '❌ Task Needs Rework',
          body: accepted
              ? 'Your proof for "${item.task.title}" was accepted.'
              : 'Your proof for "${item.task.title}" was rejected. Check comment.',
          data: {
            'type': 'task_review',
            'taskId': item.taskId,
            'status': accepted ? 'accepted' : 'rejected',
          },
        );
      }
      _showSnack(accepted ? 'Marked as accepted' : 'Marked as rejected');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<String?> _getStudentFcmToken(String studentUID) async {
    final tokenDoc = await FirebaseFirestore.instance
        .collection('fcmTokens')
        .doc(studentUID)
        .get();
    final token = tokenDoc.data()?['token']?.toString();
    if (token != null && token.isNotEmpty) return token;

    final byUid = await FirebaseFirestore.instance
        .collection('students')
        .where('uid', isEqualTo: studentUID)
        .limit(1)
        .get();
    if (byUid.docs.isNotEmpty) {
      return byUid.docs.first.data()['fcmToken']?.toString();
    }
    return null;
  }

  Future<void> _sendPushNotification({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    const backendUrl =
        'https://smartclassroommontoring-system.onrender.com/send-notification';

    await http.post(
      Uri.parse(backendUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'fcmToken': token,
        'title': title,
        'body': body,
        'data': data ?? {},
      }),
    );
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
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text('Task Center',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                .animate()
                .fadeIn(),
          ),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
              ),
              dividerColor: Colors.transparent,
              labelColor: AppColors.success,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Assign Task'),
                Tab(text: 'Review Proofs'),
              ],
            ),
          ).animate().fadeIn(delay: 100.ms),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_assignTab(), _reviewTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _assignTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              items: _classIds
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedClass = v);
                _loadStudentsForClass(v);
              },
              decoration: const InputDecoration(labelText: 'Class'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Task title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Due: ${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      initialDate: _dueDate,
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _sendAll,
              onChanged: (v) => setState(() => _sendAll = v),
              title: Text(
                _sendAll ? 'Send to all students in class' : 'Send to selected students',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
            if (!_sendAll)
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: _studentsInClass.length,
                  itemBuilder: (_, i) {
                    final s = _studentsInClass[i];
                    final uid = (s['uid'] ?? '').toString();
                    final selected = _selectedStudents.contains(uid);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: uid.isEmpty
                          ? null
                          : (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedStudents.add(uid);
                                } else {
                                  _selectedStudents.remove(uid);
                                }
                              });
                            },
                      title: Text(
                        (s['name'] ?? 'Student').toString(),
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      subtitle: Text(
                        (s['studentId'] ?? s['regNo'] ?? '').toString(),
                        style: GoogleFonts.poppins(color: AppColors.textSecondary),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _createTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                  _submitting ? 'Sending...' : 'Send Task',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewTab() {
    return StreamBuilder<List<PendingSubmissionItem>>(
      stream: _tasksService.streamPendingSubmissions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.success),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No pending proofs',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.task.title,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Student UID: ${item.submission.studentUID}',
                      style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (item.submission.proofImageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          item.submission.proofImageUrl,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _review(item, accepted: false),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.warning),
                            ),
                            child: Text(
                              'Reject',
                              style: GoogleFonts.poppins(color: AppColors.warning),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _review(item, accepted: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                            ),
                            child: Text(
                              'Accept',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
