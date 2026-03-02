import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../features/admin/notification/proof_image_preview_screen.dart';
import '../../../models/task_model.dart';
import '../../../services/student_alerts_service.dart';
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
  final StudentAlertsService _alertsService = StudentAlertsService();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _selectedClass;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  bool _sendAll = true;
  bool _submitting = false;

  List<String> _classIds = [];
  List<Map<String, dynamic>> _studentsInClass = [];
  final Set<String> _selectedStudents = {};
  final Map<String, String> _studentRegNoCache = {};

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
      final taskId = await _tasksService.createTaskAssignment(
        createdByUID: FirebaseAuth.instance.currentUser?.uid ?? '',
        targetClassId: _selectedClass!,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        dueDate: _dueDate,
        audienceType:
            _sendAll ? TaskAudienceType.allInClass : TaskAudienceType.selectedStudents,
        assigneeUIDs: _sendAll
          ? _studentsInClass
            .map((e) => e['uid'] ?? e['id'])
            .where((e) => e != null)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          : _selectedStudents.toList(),
      );

      try {
        await _createStudentTaskAlerts(taskId: taskId);
      } catch (e) {
        debugPrint('[Task Alert] Failed to create student alerts: $e');
      }

      final notified = await _notifyStudentsForNewTask(
        taskId: taskId,
        title: _titleCtrl.text.trim(),
      );

      if (notified > 0) {
        _showSnack('Task sent successfully • notified $notified students');
      } else {
        _showSnack('Task sent successfully');
      }
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
      if (reviewer.trim().isEmpty) {
        _showSnack('Session expired. Please login again.', isError: true);
        return;
      }
      await _tasksService.reviewSubmission(
        taskId: item.taskId,
        studentUID: item.submission.studentUID,
        accepted: accepted,
        reviewedByUID: reviewer,
        comment: comment,
      );

      _showSnack(accepted ? 'Marked as accepted' : 'Marked as rejected');

      final token = await _getStudentFcmToken(item.submission.studentUID);
      if (token != null && token.isNotEmpty) {
        try {
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
        } catch (_) {}
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _openProofPreview(String imageUrl) {
    if (imageUrl.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProofImagePreviewScreen(imageUrl: imageUrl),
      ),
    );
  }

  Future<String?> _getStudentFcmToken(String studentUID) async {
    return _getStudentFcmTokenFromKeys([studentUID]);
  }

  Future<String> _resolveStudentRegNo(String studentUID) async {
    final uid = studentUID.trim();
    if (uid.isEmpty) return '—';

    final cached = _studentRegNoCache[uid];
    if (cached != null && cached.isNotEmpty) return cached;

    String pickRegNo(Map<String, dynamic>? data) {
      return (data?['registrationNumber'] ??
              data?['regNo'] ??
              data?['studentId'] ??
              data?['rollNo'] ??
              '')
          .toString()
          .trim();
    }

    try {
      final byUid = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (byUid.docs.isNotEmpty) {
        final reg = pickRegNo(byUid.docs.first.data());
        if (reg.isNotEmpty) {
          _studentRegNoCache[uid] = reg;
          return reg;
        }
      }

      final byDocId = await FirebaseFirestore.instance
          .collection('students')
          .doc(uid)
          .get();
      if (byDocId.exists) {
        final reg = pickRegNo(byDocId.data());
        if (reg.isNotEmpty) {
          _studentRegNoCache[uid] = reg;
          return reg;
        }
      }
    } catch (_) {}

    return uid;
  }

  Future<String?> _getStudentFcmTokenFromKeys(List<String> keys) async {
    final candidates = <String>{
      ...keys.map((e) => e.trim()),
    }..removeWhere((e) => e.isEmpty);

    for (final key in candidates) {
      final tokenDoc = await FirebaseFirestore.instance
          .collection('fcmTokens')
          .doc(key)
          .get();
      final token = tokenDoc.data()?['token']?.toString().trim();
      if (token != null && token.isNotEmpty) return token;

      final byDocId = await FirebaseFirestore.instance
          .collection('students')
          .doc(key)
          .get();
      final docToken = byDocId.data()?['fcmToken']?.toString().trim();
      if (docToken != null && docToken.isNotEmpty) return docToken;

      final byUid = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: key)
          .limit(1)
          .get();
      if (byUid.docs.isNotEmpty) {
        final byUidToken = byUid.docs.first.data()['fcmToken']?.toString().trim();
        if (byUidToken != null && byUidToken.isNotEmpty) return byUidToken;
      }

      final byStudentId = await FirebaseFirestore.instance
          .collection('students')
          .where('studentId', isEqualTo: key)
          .limit(1)
          .get();
      if (byStudentId.docs.isNotEmpty) {
        final byStudentIdToken =
            byStudentId.docs.first.data()['fcmToken']?.toString().trim();
        if (byStudentIdToken != null && byStudentIdToken.isNotEmpty) {
          return byStudentIdToken;
        }
      }
    }
    return null;
  }

  List<String> _studentKeys(Map<String, dynamic> row) {
    final raw = [
      row['uid'],
      row['id'],
      row['studentId'],
      row['registrationNumber'],
      row['regNo'],
      row['rollNo'],
      row['email'],
      row['gmail'],
    ];
    final out = <String>[];
    final seen = <String>{};
    for (final v in raw) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  Future<int> _notifyStudentsForNewTask({
    required String taskId,
    required String title,
  }) async {
    final recipients = _sendAll
        ? List<Map<String, dynamic>>.from(_studentsInClass)
        : _studentsInClass.where((row) {
            final keys = _studentKeys(row);
            return keys.any(_selectedStudents.contains);
          }).toList();

    var notified = 0;
    for (final student in recipients) {
      try {
        final rowToken = (student['fcmToken'] ?? '').toString().trim();
        final token = rowToken.isNotEmpty
            ? rowToken
          : await _getStudentFcmTokenFromKeys(_studentKeys(student));
        if (token == null || token.isEmpty) continue;
        await _sendPushNotification(
          token: token,
          title: '📌 New Task Assigned',
          body: '"$title" task has been assigned. Open Tasks tab to view.',
          data: {
            'type': 'task_assigned',
            'taskId': taskId,
          },
        );
        notified++;
      } catch (_) {
        continue;
      }
    }
    return notified;
  }

  Future<void> _createStudentTaskAlerts({required String taskId}) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final recipients = _sendAll
        ? List<Map<String, dynamic>>.from(_studentsInClass)
        : _studentsInClass.where((row) {
            final keys = _studentKeys(row);
            return keys.any(_selectedStudents.contains);
          }).toList();

    for (final student in recipients) {
      final keys = _studentKeys(student);
      if (keys.isEmpty) continue;
      final ownerKey = (student['id'] ??
              student['registrationNumber'] ??
              student['regNo'] ??
              student['rollNo'] ??
              student['studentId'] ??
              student['uid'])
          ?.toString()
          .trim();
      await _alertsService.createTaskAlert(
        taskId: taskId,
        taskTitle: title,
        recipientKeys: keys,
        ownerKey: (ownerKey == null || ownerKey.isEmpty) ? null : ownerKey,
      );
    }
  }

  Future<void> _sendPushNotification({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    const backendUrl =
        'https://smartclassroommontoring-system.onrender.com/send-notification';

    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .post(
          Uri.parse(backendUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'fcmToken': token,
            'title': title,
            'body': body,
            'data': data ?? {},
          }),
        )
            .timeout(const Duration(seconds: 65));

        if (response.statusCode >= 200 && response.statusCode < 300) return;
        if (attempt == maxAttempts) {
          debugPrint('[Notification] Endpoint failed $backendUrl (${response.statusCode})');
        }
      } catch (e) {
        if (attempt == maxAttempts) {
          debugPrint('[Notification] Endpoint exception $backendUrl: $e');
        }
      }
    }

    throw Exception('Notification service failed on all endpoints');
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
                child: _studentsInClass.isEmpty
                    ? Center(
                        child: Text(
                          'No students found for selected class.',
                          style: GoogleFonts.poppins(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _studentsInClass.length,
                        itemBuilder: (_, i) {
                          final s = _studentsInClass[i];
                          final uid =
                              (s['uid'] ?? s['id'] ?? s['studentId'] ?? '').toString();
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
    final reviewerUID = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<PendingSubmissionItem>>(
      stream: _tasksService.streamPendingSubmissions(reviewerUID: reviewerUID),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.success),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error.toString();
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Failed to load proof reviews\n$message',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: AppColors.textSecondary),
              ),
            ),
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
                    FutureBuilder<String>(
                      future: _resolveStudentRegNo(item.submission.studentUID),
                      builder: (context, regSnapshot) {
                        final regNo = regSnapshot.data ?? '...';
                        return Text(
                          'Reg No: $regNo',
                          style: GoogleFonts.poppins(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    if (item.submission.proofImageUrl.isNotEmpty)
                      GestureDetector(
                        onTap: () => _openProofPreview(item.submission.proofImageUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            item.submission.proofImageUrl,
                            height: 170,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
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
