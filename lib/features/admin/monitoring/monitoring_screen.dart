import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  String _search = '';

  static const _students = [
    _Student('Juan Santos', 'STU001', 65, 'Chemistry'),
    _Student('Maria Cruz', 'STU002', 82, 'Mathematics'),
    _Student('Pedro Reyes', 'STU003', 71, 'Physics'),
    _Student('Ana Gomez', 'STU004', 90, 'English'),
    _Student('Carlos Ramos', 'STU005', 55, 'Chemistry'),
    _Student('Liza Torres', 'STU006', 88, 'Comp. Science'),
    _Student('Marco Lim', 'STU007', 78, 'Physics'),
    _Student('Sofia Tan', 'STU008', 95, 'Mathematics'),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _students
        .where((s) =>
            s.name.toLowerCase().contains(_search.toLowerCase()) ||
            s.id.contains(_search))
        .toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Student Monitoring',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                    .animate()
                    .fadeIn(),
                const SizedBox(height: 14),
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1),
                  ),
                  child: TextField(
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 14),
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search student...',
                      hintStyle: GoogleFonts.poppins(
                          color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16),
                    ),
                  ),
                ).animate().fadeIn(delay: 100.ms),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final s = filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => _showDetail(context, s),
                    child: _StudentTile(s).animate().fadeIn(
                        delay: Duration(milliseconds: 50 * i)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, _Student s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StudentDetailSheet(s),
    );
  }
}

class _Student {
  final String name;
  final String id;
  final int attendance;
  final String lowSubject;
  const _Student(this.name, this.id, this.attendance, this.lowSubject);

  Color get statusColor => attendance >= 80
      ? AppColors.success
      : attendance >= 70
          ? AppColors.warning
          : AppColors.danger;

  String get status => attendance >= 80
      ? 'Good'
      : attendance >= 70
          ? 'At Risk'
          : 'Critical';
}

class _StudentTile extends StatelessWidget {
  final _Student s;
  const _StudentTile(this.s);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: s.statusColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: s.statusColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded, color: s.statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(s.id,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${s.attendance}%',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: s.statusColor)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: s.statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s.status,
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: s.statusColor,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentDetailSheet extends StatelessWidget {
  final _Student s;
  const _StudentDetailSheet(this.s);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40, height: 4, color: Colors.white24,
              margin: const EdgeInsets.only(bottom: 20)),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.statusColor.withValues(alpha: 0.2),
            ),
            child: Icon(Icons.person_rounded, size: 36, color: s.statusColor),
          ),
          const SizedBox(height: 12),
          Text(s.name,
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(s.id,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          _DetailRow('Overall Attendance', '${s.attendance}%', s.statusColor),
          const Divider(color: Colors.white12, height: 20),
          _DetailRow('Status', s.status, s.statusColor),
          const Divider(color: Colors.white12, height: 20),
          _DetailRow('Low Subject', s.lowSubject, AppColors.warning),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning.withValues(alpha: 0.2),
                foregroundColor: AppColors.warning,
                side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.notifications_active_rounded, size: 20),
              label: Text('Send Alert',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _DetailRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.textSecondary)),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }
}
