import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/admin_dashboard_service.dart';

class AdminViolationsScreen extends StatefulWidget {
  const AdminViolationsScreen({super.key});

  @override
  State<AdminViolationsScreen> createState() => _AdminViolationsScreenState();
}

class _AdminViolationsScreenState extends State<AdminViolationsScreen> {
  late final AdminDashboardService _service;
  late final Stream<List<AdminAlertRow>> _stream;

  List<AdminAlertRow> _items = [];
  bool _loading = true;
  bool _exportingPdf = false;

  StreamSubscription<List<AdminAlertRow>>? _sub;

  @override
  void initState() {
    super.initState();
    _service = AdminDashboardService();
    _stream = _service.streamLast2DaysAlertsList();
    _sub = _stream.listen((items) {
      if (mounted) setState(() { _items = items; _loading = false; });
    }, onError: (_) {
      if (mounted) setState(() { _loading = false; });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h  = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final m  = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    final day   = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$h:$m $ap  •  $day/$month/${local.year}';
  }

  Future<void> _downloadPdf() async {
    if (_items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No violations available to download')),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      final doc = pw.Document();
      final dateFormat = DateFormat('dd/MM/yyyy hh:mm a');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Text(
                'Violations Report (Last 48 hours)',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Generated on: ${dateFormat.format(DateTime.now())}'),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: const ['Name', 'Reg No', 'Period', 'Seconds', 'Timestamp'],
                data: _items
                    .map((item) => [
                          item.name,
                          item.regNo,
                          item.period,
                          '${item.secondsUsed}s',
                          dateFormat.format(item.timestamp.toLocal()),
                        ])
                    .toList(),
              ),
            ];
          },
        ),
      );

      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'violations_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Violations',
                          style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white))
                          .animate().fadeIn(),
                      Text('Last 48 hours • Phone usage during class',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.textSecondary))
                          .animate().fadeIn(delay: 100.ms),
                    ],
                  ),
                ),
                // Count badge
                if (!_loading)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${_items.length}',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger),
                    ),
                  ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _exportingPdf ? null : _downloadPdf,
                  tooltip: 'Download PDF',
                  icon: _exportingPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(
                          Icons.download_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Body ─────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.danger))
                : _items.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final v = _items[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left — red indicator dot
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.phone_android_rounded,
                      color: AppColors.danger, size: 20),
                ),
                const SizedBox(width: 14),
                // Right — details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + seconds badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(v.name,
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${v.secondsUsed}s',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.danger)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _InfoRow(
                          Icons.badge_outlined, 'Reg No', v.regNo),
                      const SizedBox(height: 4),
                      _InfoRow(
                          Icons.schedule_rounded, 'Period', v.period),
                      const SizedBox(height: 4),
                      _InfoRow(
                          Icons.access_time_rounded,
                          'Time',
                          _formatTime(v.timestamp)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 50)),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 64, color: AppColors.success.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text('No violations in the last 48 hours.',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
          const SizedBox(height: 6),
          Text('All students are following the rules.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ).animate().fadeIn(),
    );
  }
}

// ── Info row widget ───────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text('$label: ',
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
