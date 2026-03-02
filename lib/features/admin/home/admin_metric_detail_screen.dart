import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/admin_dashboard_service.dart';

class AdminMetricDetailScreen extends StatelessWidget {
  final String title;
  final Stream<List<AdminStudentRow>>? studentsStream;
  final Stream<List<AdminAlertRow>>? alertsStream;

  const AdminMetricDetailScreen({
    super.key,
    required this.title,
    this.studentsStream,
    this.alertsStream,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: alertsStream != null
                      ? _buildAlertsList(alertsStream!)
                      : _buildStudentsList(studentsStream!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentsList(Stream<List<AdminStudentRow>> stream) {
    return StreamBuilder<List<AdminStudentRow>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.lightBlue),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load list',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          );
        }
        final rows = snapshot.data ?? const <AdminStudentRow>[];
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'No records found',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          );
        }

        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.lightBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_rounded, color: AppColors.lightBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.name,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.regNo.isEmpty ? row.classLabel : '${row.regNo} • ${row.classLabel}',
                            style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlertsList(Stream<List<AdminAlertRow>> stream) {
    return StreamBuilder<List<AdminAlertRow>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.lightBlue),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load alerts',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          );
        }
        final rows = snapshot.data ?? const <AdminAlertRow>[];
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'No alerts in current day window',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          );
        }

        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.warning_rounded, color: AppColors.danger),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.name,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.regNo.isEmpty ? row.period : '${row.regNo} • ${row.period}',
                            style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('dd MMM, hh:mm a').format(row.timestamp),
                            style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}