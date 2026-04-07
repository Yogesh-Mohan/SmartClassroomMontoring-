import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/cloudinary_upload_service.dart';
import '../../../services/credits_service.dart';

class UploadCertificateScreen extends StatelessWidget {
  final String studentId;
  final String studentName;
  final String semester;
  const UploadCertificateScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.semester,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => _UploadCertificateController(),
      child: _UploadCertificateView(
        studentId: studentId,
        studentName: studentName,
        semester: semester,
      ),
    );
  }
}

class _UploadCertificateView extends StatelessWidget {
  final String studentId;
  final String studentName;
  final String semester;
  const _UploadCertificateView({
    required this.studentId,
    required this.studentName,
    required this.semester,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<_UploadCertificateController>();
    return Scaffold(
      backgroundColor: AppColors.gradientStart,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Upload Certificate',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Attach proof to claim activity credits.',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 20),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Certificate Title',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            TextField(
                              onChanged: controller.updateTitle,
                              decoration: _inputDecoration('Eg. Hackathon Winner'),
                            ),
                            const SizedBox(height: 16),
                            Text('Description (optional)',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            TextField(
                              minLines: 2,
                              maxLines: 4,
                              onChanged: controller.updateDescription,
                              decoration:
                                  _inputDecoration('Share highlights or scope...'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: controller.uploading ? null : () => controller.pickFile(),
                        child: GlassCard(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.lightBlue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.attach_file_rounded,
                                    color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: controller.selectedFile == null
                                    ? Text('PDF / JPG / PNG • Max 5 MB',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white70, fontSize: 13))
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(controller.selectedFile!.name,
                                              style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600)),
                                          Text(
                                              '${controller.selectedFileSizeMb.toStringAsFixed(2)} MB',
                                              style: GoogleFonts.poppins(
                                                  color: Colors.white54, fontSize: 12)),
                                        ],
                                      ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white54),
                            ],
                          ),
                        ),
                      ),
                      if (controller.errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(controller.errorMessage!,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppColors.danger)),
                      ],
                      const SizedBox(height: 16),
                      if (controller.uploading) ...[
                        LinearProgressIndicator(
                          value: controller.progress,
                          color: AppColors.lightBlue,
                          backgroundColor: Colors.white24,
                        ),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton.icon(
                        onPressed: controller.canSubmit
                            ? () async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  await controller.upload(
                                    studentId: studentId,
                                    studentName: studentName,
                                    semester: semester,
                                  );
                                  if (!context.mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Certificate submitted for approval.',
                                          style: GoogleFonts.poppins()),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                  if (context.mounted) Navigator.of(context).pop();
                                } catch (e) {
                                  if (!context.mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString(),
                                          style: GoogleFonts.poppins()),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.lightBlue,
                          disabledBackgroundColor: Colors.white24,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: controller.uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                        label: Text(
                          controller.uploading ? 'Uploading...' : 'Submit for Review',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white, width: 1.2),
      ),
    );
  }
}

class _UploadCertificateController extends ChangeNotifier {
  PlatformFile? selectedFile;
  Uint8List? _bytes;
  double progress = 0;
  bool uploading = false;
  String? errorMessage;
  String _title = '';
  String _description = '';
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifySafe() {
    if (_disposed) return;
    notifyListeners();
  }

  double get selectedFileSizeMb =>
      selectedFile == null ? 0 : selectedFile!.size / (1024 * 1024);

  bool get canSubmit =>
      !uploading && selectedFile != null && _title.trim().isNotEmpty;

  void updateTitle(String value) {
    _title = value;
    _notifySafe();
  }

  void updateDescription(String value) {
    _description = value;
  }

  Future<void> pickFile() async {
    errorMessage = null;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.size > 5 * 1024 * 1024) {
      errorMessage = 'File exceeds 5 MB limit.';
      _notifySafe();
      return;
    }
    if (file.bytes == null) {
      errorMessage = 'Unable to read file. Please try another document.';
      _notifySafe();
      return;
    }
    selectedFile = file;
    _bytes = file.bytes;
    _notifySafe();
  }

  Future<void> upload({
    required String studentId,
    required String studentName,
    required String semester,
  }) async {
    if (!canSubmit) {
      throw Exception('Add a title and attach the certificate file.');
    }
    uploading = true;
    progress = 0;
    errorMessage = null;
    _notifySafe();

    try {
      final ext = (selectedFile!.extension ?? '').toLowerCase();
      final contentType = _mimeFromExtension(ext);
      final safeName =
          '${DateTime.now().millisecondsSinceEpoch}_${selectedFile!.name.replaceAll(' ', '_')}';
      progress = 0.4;
      _notifySafe();

      final url = await CloudinaryUploadService.uploadBytes(
        bytes: _bytes!,
        fileName: safeName,
        contentType: contentType,
        resourceType: ext == 'pdf' ? 'raw' : 'image',
        folder: 'certificates/$studentId/$semester',
      );

      progress = 0.85;
      _notifySafe();

      await CreditsService.instance.createCertificateRecord(
        studentId: studentId,
        studentUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        studentName: studentName,
        semester: semester,
        title: _title.trim(),
        fileUrl: url,
        fileType: ext,
        fileSizeMb: selectedFileSizeMb,
        description: _description.trim().isEmpty ? null : _description.trim(),
      );
      uploading = false;
      progress = 1;
      _notifySafe();
    } catch (e) {
      uploading = false;
      errorMessage = e.toString();
      _notifySafe();
      rethrow;
    }
  }
}

String _mimeFromExtension(String ext) {
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    default:
      return 'application/octet-stream';
  }
}
