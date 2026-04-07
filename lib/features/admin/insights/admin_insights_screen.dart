import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

class AdminInsightsScreen extends StatelessWidget {
  const AdminInsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insights',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Realtime summary from Firestore',
              style: GoogleFonts.poppins(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('live_monitoring')
                    .snapshots(),
                builder: (context, liveSnapshot) {
                  final liveDocs = liveSnapshot.data?.docs ?? const [];
                  final online = liveDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final status = (data['status'] ?? '').toString().toLowerCase();
                    return status == 'active' || status == 'idle';
                  }).length;

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('violations')
                        .orderBy('timestamp', descending: true)
                        .limit(200)
                        .snapshots(),
                    builder: (context, violationSnapshot) {
                      final violationDocs = violationSnapshot.data?.docs ?? const [];
                      final now = DateTime.now();
                      final todayCount = violationDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>? ?? {};
                        final ts = data['timestamp'];
                        if (ts is! Timestamp) return false;
                        final dt = ts.toDate();
                        return dt.year == now.year &&
                            dt.month == now.month &&
                            dt.day == now.day;
                      }).length;

                      return ListView(
                        children: [
                          _MetricCard(
                            title: 'Students Online',
                            value: '$online',
                            color: AppColors.success,
                            subtitle: 'From live monitoring stream',
                          ),
                          const SizedBox(height: 12),
                          _MetricCard(
                            title: 'Violations Today',
                            value: '$todayCount',
                            color: AppColors.warning,
                            subtitle: 'Counted from violations collection',
                          ),
                          const SizedBox(height: 12),
                          _MetricCard(
                            title: 'Tracked Students',
                            value: '${liveDocs.length}',
                            color: AppColors.info,
                            subtitle: 'Students visible in live_monitoring',
                          ),
                        ],
                      );
                    },
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

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
