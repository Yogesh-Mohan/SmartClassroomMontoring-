import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/credits_service.dart';

class InteractionScoreDashboard extends StatelessWidget {
  final Map<String, dynamic> studentData;
  const InteractionScoreDashboard({super.key, required this.studentData});

  String get _studentId {
    return (studentData['id'] ??
            studentData['studentId'] ??
            studentData['registrationNumber'] ??
            studentData['uid'] ??
            '')
        .toString();
  }

  String get _semester {
    return (studentData['semester'] ??
            studentData['sem'] ??
            studentData['currentSemester'] ??
            'S1')
        .toString();
  }

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
                    Text(
                      'Interaction Dashboard',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Subject-wise scores • Semester $_semester',
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<InteractionDashboardItem>>(
                  stream: CreditsService.instance.streamInteractionDashboard(
                    studentId: _studentId,
                    semester: _semester,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Failed to load interaction scores.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(color: Colors.white70),
                          ),
                        ),
                      );
                    }

                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          'No interaction score yet.',
                          style: GoogleFonts.poppins(color: Colors.white70),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.subjectName,
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${item.subjectTotalScore.toStringAsFixed(1)}/10',
                                      style: GoogleFonts.poppins(
                                        color: AppColors.lightBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _InfoRow(
                                  label: 'Interaction Boost %',
                                  value: '${item.interactionBoostPercent.toStringAsFixed(1)}%',
                                ),
                                const SizedBox(height: 6),
                                _InfoRow(
                                  label: 'Boost Points',
                                  value: '+${item.interactionBoost.toStringAsFixed(2)}',
                                ),
                                const SizedBox(height: 6),
                                _InfoRow(
                                  label: 'Updated Subject Internal',
                                  value: item.updatedSubjectInternal.toStringAsFixed(2),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
