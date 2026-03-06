import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../models/credits_models.dart';
import '../../../services/credits_service.dart';
import 'upload_certificate_screen.dart';

class CreditsScreen extends StatelessWidget {
  final Map<String, dynamic> studentData;
  const CreditsScreen({super.key, required this.studentData});

  String get _studentAcademicId {
    return (studentData['studentId'] ??
            studentData['registrationNumber'] ??
            studentData['regNo'] ??
            studentData['rollNo'] ??
            studentData['id'] ??
            studentData['uid'] ??
            FirebaseAuth.instance.currentUser?.uid ??
            '')
        .toString()
        .trim();
  }

  String get _studentUid {
    return (FirebaseAuth.instance.currentUser?.uid ?? studentData['uid'] ?? '')
        .toString()
        .trim();
  }

  String get _studentName => (studentData['name'] ?? 'Student').toString();

  String get _semester {
    return (studentData['semester'] ??
            studentData['sem'] ??
            studentData['currentSemester'] ??
            'S1')
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final stream = CreditsService.instance.streamStudentDashboard(
      studentId: _studentAcademicId,
      studentUid: _studentUid,
      semester: _semester,
    );

    return Scaffold(
      backgroundColor: AppColors.gradientStart,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.lightBlue,
        icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
        label: Text('Upload Certificate',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UploadCertificateScreen(
                studentId: _studentAcademicId,
                studentName: _studentName,
                semester: _semester,
              ),
            ),
          );
        },
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: SafeArea(
          child: StreamBuilder<CreditsDashboardState>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                );
              }

              final state = snapshot.data ??
                  const CreditsDashboardState(
                    monthlyActivityScore: 0,
                    semesterActivityScore: 0,
                    activityBoostPoints: 0,
                    activityBoostPercent: 0,
                    interactionSubjects: [],
                    internalMarks: [],
                  );

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(child: _buildActivitySection(state)),
                  SliverToBoxAdapter(child: _buildInteractionSection(state)),
                  SliverToBoxAdapter(child: _buildBoostSummary(state)),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: AppGradients.blueGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                const Icon(Icons.stars_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Credits Dashboard',
                        style: GoogleFonts.poppins(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ))
                    .animate()
                    .fadeIn(duration: 400.ms),
                Text('Semester $_semester • $_studentName',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActivitySection(CreditsDashboardState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  child: _MetricTile(
                    label: 'Monthly Score',
                    value: state.monthlyActivityScore.toStringAsFixed(1),
                    subtitle: 'Current month',
                    icon: Icons.calendar_month_rounded,
                    color: AppColors.lightBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassCard(
                  child: _MetricTile(
                    label: 'Semester Score',
                    value: state.semesterActivityScore.toStringAsFixed(1),
                    subtitle: 'Accumulated',
                    icon: Icons.timeline_rounded,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: _MetricTile(
              label: 'Activity Boost %',
              value: '${state.activityBoostPercent.toStringAsFixed(1)}%',
              subtitle:
                  '+${state.activityBoostPoints.toStringAsFixed(2)} internal points',
              icon: Icons.trending_up_rounded,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionSection(CreditsDashboardState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Interaction Scores',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Subject-wise',
                  style: GoogleFonts.poppins(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w400)),
            ],
          ),
          const SizedBox(height: 12),
          if (state.interactionSubjects.isEmpty)
            GlassCard(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                child: Text('No interaction scores yet.',
                    style: GoogleFonts.poppins(color: Colors.white70)),
              ),
            )
          else
            Column(
              children: state.interactionSubjects.map((subject) {
                final progress = (subject.totalScore / 10).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(subject.subjectName,
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                            ),
                            Text('${subject.totalScore.toStringAsFixed(1)}/10',
                                style: GoogleFonts.poppins(
                                    color: AppColors.lightBlue,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(
                              progress >= 0.9
                                  ? AppColors.success
                                  : AppColors.lightBlue,
                            ),
                          ),
                        ),
                        if (subject.entries.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('Latest: ${subject.entries.first.topic}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.white70)),
                        ]
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBoostSummary(CreditsDashboardState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Final Internal Preview',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (state.internalMarks.isEmpty)
            GlassCard(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                child: Text('Internal marks will appear once teachers publish.',
                    style: GoogleFonts.poppins(color: Colors.white70)),
              ),
            )
          else
            Column(
              children: state.internalMarks.map((mark) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(mark.subjectName,
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                            ),
                            Text('${mark.finalInternal.toStringAsFixed(1)} / 100',
                                style: GoogleFonts.poppins(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _TagChip('Base ${mark.baseInternal.toStringAsFixed(1)}'),
                            _TagChip(
                                'Activity +${mark.activityBoost.toStringAsFixed(1)}'),
                            _TagChip(
                                'Interaction +${mark.interactionBoost.toStringAsFixed(1)}'),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _MetricTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9))),
              Text(subtitle,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.white54)),
            ],
          ),
        )
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
    );
  }
}
