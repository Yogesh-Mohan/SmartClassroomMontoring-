import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../auth/student_auth_service.dart';
import '../../role_select/role_select_screen.dart';
import '../../../services/attendance_service.dart';
import '../student_profile_service.dart';

class StudentProfileScreen extends StatelessWidget {
  final Map<String, dynamic> studentData;
  const StudentProfileScreen({super.key, required this.studentData});

  String get _email =>
      (studentData['gmail'] ?? studentData['email'] ?? '').toString().trim().toLowerCase();

  Future<void> _logout(BuildContext context, Map<String, dynamic> profileData) async {
    final classId = (profileData['className'] ??
            profileData['class'] ??
            profileData['classId'] ??
            profileData['section'] ??
            profileData['course'] ??
            profileData['batch'] ??
            '')
        .toString()
        .trim();

    try {
      final result = await AttendanceService.instance.handleLogout(
        studentData: profileData,
        classId: classId,
      );

      if (!result.allowed) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.reason, style: GoogleFonts.poppins(fontSize: 13)),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logout processing failed: ${e.toString().replaceFirst('Exception: ', '')}',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await StudentAuthService.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (ctx, a1, a2) => const RoleSelectScreen(),
        transitionsBuilder: (ctx, anim, a2, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: StudentProfileService().streamProfile(_email),
          builder: (context, snapshot) {
            final data      = snapshot.data ?? studentData;
            final name      = (data['name']         ?? '—').toString();
            final gmail     = (data['gmail']         ?? data['email'] ?? '—').toString();
            final studentId = (data['studentId']     ?? '—').toString();
            final dept      = (data['department']    ?? data['course'] ?? '—').toString();
            final batch     = (data['batch']         ?? data['year']?.toString() ?? '—').toString();
            final dob       = (data['dob']           ?? data['DOB'] ?? '—').toString();
            final mentor    = (data['mentorName']    ?? data['mentor'] ?? '—').toString();
            final family    = (data['familyMembers']?.toString() ?? '—');

            final cards = [
              _CardData('Name',           name,      Icons.person_rounded,
                  const LinearGradient(colors: [Color(0xFF6A5ACD), Color(0xFF4535C1)])),
              _CardData('Batch',          batch,     Icons.school_rounded,
                  const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF00897B)])),
              _CardData('Department',     dept,      Icons.apartment_rounded,
                  const LinearGradient(colors: [Color(0xFFFF9A3C), Color(0xFFE07B00)])),
              _CardData('Mentor Name',    mentor,    Icons.person_pin_rounded,
                  const LinearGradient(colors: [Color(0xFFE84545), Color(0xFFB71C1C)])),
              _CardData('Family Members', family,    Icons.people_rounded,
                  const LinearGradient(colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)])),
              _CardData('DOB',            dob,       Icons.cake_rounded,
                  const LinearGradient(colors: [Color(0xFF78909C), Color(0xFF455A64)])),
              _CardData('Student ID',     studentId, Icons.badge_rounded,
                  const LinearGradient(colors: [Color(0xFF8E24AA), Color(0xFF6A1B9A)])),
              _CardData('Gmail',          gmail,     Icons.email_rounded,
                  const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF1B5E20)])),
            ];

            return Column(
              children: [
                Text('Profile',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                    .animate().fadeIn(),
                const SizedBox(height: 20),

                // Avatar
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.blueGradient,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.lightBlue.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: const Icon(Icons.person_rounded,
                      size: 44, color: Colors.white),
                ).animate().fadeIn(delay: 100.ms).scale(
                    begin: const Offset(0.7, 0.7),
                    curve: Curves.easeOutBack),

                const SizedBox(height: 10),
                Text(name,
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                    .animate().fadeIn(delay: 180.ms),
                Text(studentId,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary))
                    .animate().fadeIn(delay: 220.ms),
                const SizedBox(height: 24),

                // 2-column colorful card grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.45,
                  ),
                  itemBuilder: (context, i) {
                    return _InfoCard(data: cards[i])
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 260 + i * 55))
                        .slideY(begin: 0.12, end: 0);
                  },
                ),

                const SizedBox(height: 28),

                // Logout
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.danger.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _logout(context, data),
                      icon: const Icon(Icons.logout_rounded,
                          color: Colors.white, size: 22),
                      label: Text('Logout',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 520.ms),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CardData {
  final String label, value;
  final IconData icon;
  final Gradient gradient;
  const _CardData(this.label, this.value, this.icon, this.gradient);
}

class _InfoCard extends StatelessWidget {
  final _CardData data;
  const _InfoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: data.gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -14,
            bottom: -14,
            child: Icon(data.icon,
                size: 72, color: Colors.white.withValues(alpha: 0.12)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(data.icon, color: Colors.white, size: 26),
                const SizedBox(height: 2),
                Text(data.label,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.8))),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(data.value,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
