import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class AdminViolationsScreen extends StatefulWidget {
  const AdminViolationsScreen({super.key});

  @override
  State<AdminViolationsScreen> createState() => _AdminViolationsScreenState();
}

class _AdminViolationsScreenState extends State<AdminViolationsScreen> {
  List<_ViolationItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('violations')
          .orderBy('timestamp', descending: true)
          .get();

      final list = snap.docs.map((doc) {
        final d = doc.data();
        return _ViolationItem(
          name        : (d['name']        ?? '—').toString(),
          regNo       : (d['regNo']       ?? '—').toString(),
          period      : (d['period']      ?? '—').toString(),
          secondsUsed : (d['secondsUsed'] as num?)?.toInt() ?? 0,
          timestamp   : d['timestamp'] as Timestamp?,
        );
      }).toList();

      setState(() { _items = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate().toLocal();
    final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    final day   = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$h:$m $ap  •  $day/$month/${dt.year}';
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
                      Text('Phone usage during class time',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.textSecondary))
                          .animate().fadeIn(delay: 100.ms),
                    ],
                  ),
                ),
                // Count badge
                if (!_loading && _error == null)
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
                // Refresh button
                IconButton(
                  onPressed: _fetch,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white70, size: 22),
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
                : _error != null
                    ? _buildError()
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
          Text('No violations found.',
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

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 56, color: AppColors.danger.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text('Failed to load violations',
              style: GoogleFonts.poppins(
                  fontSize: 15, color: Colors.white70)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.withValues(alpha: 0.2),
              foregroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _fetch,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('Retry', style: GoogleFonts.poppins()),
          ),
        ],
      ).animate().fadeIn(),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class _ViolationItem {
  final String    name;
  final String    regNo;
  final String    period;
  final int       secondsUsed;
  final Timestamp? timestamp;

  const _ViolationItem({
    required this.name,
    required this.regNo,
    required this.period,
    required this.secondsUsed,
    required this.timestamp,
  });
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
