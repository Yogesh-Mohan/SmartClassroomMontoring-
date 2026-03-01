import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/widgets/glass_card.dart';
import '../../services/credits_service.dart';

class AddInteractionScoreScreen extends StatefulWidget {
  final Map<String, dynamic> teacherData;
  const AddInteractionScoreScreen({super.key, required this.teacherData});

  @override
  State<AddInteractionScoreScreen> createState() => _AddInteractionScoreScreenState();
}

class _AddInteractionScoreScreenState extends State<AddInteractionScoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final _scoreController = TextEditingController();

  String? _selectedStudentId;
  String? _selectedStudentName;
  String _subjectId = 'subject-1';
  String _subjectName = 'Subject';
  String _semester = 'S1';
  bool _submitting = false;

  @override
  void dispose() {
    _topicController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientStart,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Add Interaction Score',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Teacher scoring panel',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    children: [
                      GlassCard(child: _buildStudentPicker()),
                      const SizedBox(height: 12),
                      GlassCard(child: _buildSubjectFields()),
                      const SizedBox(height: 12),
                      GlassCard(child: _buildScoreForm()),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(double.infinity, 52),
                    disabledBackgroundColor: Colors.white24,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, color: Colors.white),
                  label: Text(
                    _submitting ? 'Submitting...' : 'Submit Interaction Score',
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Student',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('students').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LinearProgressIndicator(color: Colors.white70);
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Text('No students found.',
                  style: GoogleFonts.poppins(color: Colors.white70));
            }

            return DropdownButtonFormField<String>(
              initialValue: _selectedStudentId,
              dropdownColor: const Color(0xFF1E2344),
              decoration: _inputDecoration('Choose student'),
              items: docs.map((doc) {
                final data = doc.data();
                final name = (data['name'] ?? data['studentName'] ?? doc.id).toString();
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(name,
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedStudentId = value;
                  final selected = docs.firstWhere((doc) => doc.id == value).data();
                  _selectedStudentName =
                      (selected['name'] ?? selected['studentName'] ?? 'Student')
                          .toString();
                  _semester = (selected['semester'] ?? selected['sem'] ?? 'S1').toString();
                });
              },
              validator: (value) => value == null ? 'Student is required' : null,
            );
          },
        )
      ],
    );
  }

  Widget _buildSubjectFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Subject Details',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextFormField(
          onChanged: (value) => _subjectName = value,
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: _inputDecoration('Subject name'),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? 'Subject is required' : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          onChanged: (value) => _subjectId = value,
          initialValue: _subjectId,
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: _inputDecoration('Subject ID (example: cs101)'),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? 'Subject ID is required' : null,
        ),
      ],
    );
  }

  Widget _buildScoreForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Interaction Entry',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _topicController,
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: _inputDecoration('Topic name / Question'),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? 'Topic is required' : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _scoreController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: _inputDecoration('Score (0 - 10)'),
          validator: (value) {
            final parsed = double.tryParse(value ?? '');
            if (parsed == null) return 'Valid score required';
            if (parsed < 0 || parsed > 10) return 'Score must be 0-10';
            return null;
          },
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentId == null || _selectedStudentName == null) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await CreditsService.instance.addInteractionScore(
        teacherId: (widget.teacherData['id'] ?? widget.teacherData['uid'] ?? '').toString(),
        teacherName: (widget.teacherData['name'] ?? 'Teacher').toString(),
        studentId: _selectedStudentId!,
        studentName: _selectedStudentName!,
        subjectId: _subjectId.trim(),
        subjectName: _subjectName.trim().isEmpty ? 'Subject' : _subjectName.trim(),
        semester: _semester,
        topic: _topicController.text.trim(),
        score: double.parse(_scoreController.text.trim()),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Interaction score saved and internal updated.',
              style: GoogleFonts.poppins()),
          backgroundColor: AppColors.success,
        ),
      );
      _topicController.clear();
      _scoreController.clear();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: GoogleFonts.poppins()),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white, width: 1.1),
      ),
    );
  }
}

class AddInteractionScreen extends AddInteractionScoreScreen {
  const AddInteractionScreen({super.key, required super.teacherData});
}
