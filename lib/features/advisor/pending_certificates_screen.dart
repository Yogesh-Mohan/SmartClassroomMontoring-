import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/widgets/glass_card.dart';
import '../../models/credits_models.dart';
import '../../services/credits_service.dart';

class PendingCertificatesScreen extends StatefulWidget {
  final Map<String, dynamic> advisorData;
  const PendingCertificatesScreen({super.key, required this.advisorData});

  @override
  State<PendingCertificatesScreen> createState() => _PendingCertificatesScreenState();
}

class _PendingCertificatesScreenState extends State<PendingCertificatesScreen> {
  final _service = CreditsService.instance;

  String get _advisorId => (widget.advisorData['id'] ?? widget.advisorData['uid'] ?? '').toString();
  String get _advisorName => (widget.advisorData['name'] ?? 'Advisor').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientStart,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Advisor Desk',
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Review and score student certificates',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<CertificateRequest>>(
                  stream: _service.streamPendingCertificates(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white70),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Failed to load pending certificates.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      );
                    }

                    final items = snapshot.data ?? const <CertificateRequest>[];
                    if (items.isEmpty) {
                      return Center(
                        child: Text('No pending certificates.',
                            style: GoogleFonts.poppins(
                                color: Colors.white70, fontSize: 14)),
                      );
                    }

                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                                const SizedBox(height: 4),
                                Text('${item.studentName} • Sem ${item.semester}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, color: Colors.white70)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    _Badge('File: ${item.fileType.toUpperCase()}'),
                                    _Badge('${item.fileSizeMb.toStringAsFixed(2)} MB'),
                                    _Badge('Submitted ${_relativeTime(item.submittedAt)}'),
                                  ],
                                ),
                                if (item.description?.isNotEmpty == true) ...[
                                  const SizedBox(height: 8),
                                  Text(item.description!,
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.white70,
                                          height: 1.4)),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _openCertificate(item),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.visibility_rounded, size: 18),
                                              SizedBox(width: 6),
                                              Text('View'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _showApproveDialog(item),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                        ),
                                        child: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Approve'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _showRejectDialog(item),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.danger,
                                        ),
                                        child: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Reject'),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<String> _resolveCertificateUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      throw Exception('Certificate link is empty');
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(url).getDownloadURL();
    }
    return FirebaseStorage.instance.ref(url).getDownloadURL();
  }

  List<String> _previewUrlCandidates(String resolvedUrl) {
    final base = resolvedUrl.trim();
    final candidates = <String>{};
    if (base.isNotEmpty) {
      candidates.add(base);
      candidates.add(Uri.encodeFull(base));
    }

    if (base.contains('res.cloudinary.com') && base.contains('/upload/')) {
      final transformed = base.replaceFirst(
        '/upload/',
        '/upload/f_auto,q_auto/',
      );
      candidates.add(transformed);
      candidates.add(Uri.encodeFull(transformed));
    }

    return candidates.where((e) => e.isNotEmpty).toList(growable: false);
  }

  Future<bool> _isDecodableImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      await codec.getNextFrame();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> _fetchPreviewImageBytes(String resolvedUrl) async {
    final candidates = _previewUrlCandidates(resolvedUrl);
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      if (uri == null) continue;

      try {
        final response = await http.get(uri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final bytes = response.bodyBytes;
        if (bytes.isEmpty) continue;

        final contentType =
            (response.headers['content-type'] ?? '').toLowerCase();
        if (contentType.startsWith('image/')) {
          return bytes;
        }

        final decodable = await _isDecodableImage(bytes);
        if (decodable) {
          return bytes;
        }
      } catch (_) {
        continue;
      }
    }

    throw Exception('This file cannot be previewed as image.');
  }

  Future<void> _showImagePreview(String resolvedUrl) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: FutureBuilder<Uint8List>(
                    future: _fetchPreviewImageBytes(resolvedUrl),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        );
                      }

                      if (snapshot.hasError || !snapshot.hasData) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              'This file cannot be previewed as image.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(color: Colors.white70),
                            ),
                          ),
                        );
                      }

                      return InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCertificate(CertificateRequest request) async {
    try {
      final resolvedUrl = await _resolveCertificateUrl(request.fileUrl);
      await _showImagePreview(resolvedUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open certificate. ${e.toString().replaceFirst('Exception: ', '')}',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showApproveDialog(CertificateRequest request) async {
    final controller = TextEditingController();
    final score = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Approve Certificate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter score (0 - 10). Monthly cap 10 pts.',
                  style: GoogleFonts.poppins(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'Score'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value == null) return;
                Navigator.of(ctx).pop(value);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (score == null) return;
    _processApprove(request, score);
  }

  Future<void> _processApprove(CertificateRequest request, double score) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.approveCertificate(
        certificateId: request.id,
        advisorId: _advisorId,
        advisorName: _advisorName,
        score: score,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Approved with $score pts.',
              style: GoogleFonts.poppins()),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: GoogleFonts.poppins()),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showRejectDialog(CertificateRequest request) async {
    final controller = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reject Certificate'),
          content: TextField(
            controller: controller,
            decoration:
                const InputDecoration(hintText: 'Reason (optional)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.rejectCertificate(
        certificateId: request.id,
        advisorId: _advisorId,
        reason: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Certificate rejected.',
              style: GoogleFonts.poppins()),
          backgroundColor: AppColors.warning,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: GoogleFonts.poppins()),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
    );
  }
}
