import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/smart_attendance_service.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;

  const StudentAttendanceScreen({super.key, required this.studentData});

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  final SmartAttendanceService _service = SmartAttendanceService.instance;
  final TextEditingController _codeController = TextEditingController();

  String? _selectedPeriod;
  bool _periodLoading = true;
  bool _submitting = false;
  String? _status;
  Color _statusColor = AppColors.info;

  @override
  void initState() {
    super.initState();
    _loadCurrentPeriod();
  }

  Future<void> _loadCurrentPeriod() async {
    final period = await _service.getCurrentClassPeriod();
    if (!mounted) return;

    setState(() {
      _selectedPeriod = period;
      _periodLoading = false;
      if (period == null) {
        _status = 'No active class period right now.';
        _statusColor = AppColors.warning;
      }
    });
  }

  String get _studentName {
    return (widget.studentData['name'] ??
            widget.studentData['studentName'] ??
            'Student')
        .toString();
  }

  Future<void> _submit() async {
    final period = _selectedPeriod;
    if (period == null || period.isEmpty) {
      setState(() {
        _status = 'No active class period right now.';
        _statusColor = AppColors.warning;
      });
      return;
    }

    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _status = 'Please enter attendance code';
        _statusColor = AppColors.warning;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _status = null;
    });

    final result = await _service.submitAttendance(
      code: code,
      period: period,
      studentName: _studentName,
    );

    if (!mounted) return;

    setState(() {
      _submitting = false;
      _status = result.message;
      _statusColor = result.success ? AppColors.success : AppColors.danger;
    });

    if (result.success) {
      _codeController.clear();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark Attendance',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Period',
                    style: GoogleFonts.poppins(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0x332E5BFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _periodLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Detecting current class period...',
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                            ],
                          )
                        : Text(
                            _selectedPeriod ?? 'No active class period',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter attendance code',
                      hintStyle: GoogleFonts.poppins(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: const Color(0x221FD4FF),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_submitting || _periodLoading || _selectedPeriod == null)
                          ? null
                          : _submit,
                      child: Text(_submitting ? 'Submitting...' : 'Submit'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_status != null)
              GlassCard(
                child: Text(
                  _status!,
                  style: GoogleFonts.poppins(
                    color: _statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            GlassCard(
              child: Text(
                'Validation includes code check, session time, active status, and duplicate prevention.',
                style: GoogleFonts.poppins(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
