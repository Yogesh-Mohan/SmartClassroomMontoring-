import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../auth/admin_auth_service.dart';
import '../../role_select/role_select_screen.dart';
import '../admin_profile_service.dart';

class AdminProfileScreen extends StatelessWidget {
  final Map<String, dynamic> adminData;
  const AdminProfileScreen({super.key, required this.adminData});

  String get _email =>
      (adminData['gmail'] ?? adminData['email'] ?? '').toString().trim().toLowerCase();

  Future<void> _logout(BuildContext context) async {
    try {
      await AdminAuthService.signOut();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logout failed: ${e.toString().replaceFirst('Exception: ', '')}',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: StreamBuilder<Map<String, dynamic>>(
          stream: AdminProfileService.streamProfile(_email),
          builder: (context, snapshot) {
            final data       = snapshot.data ?? adminData;
            final name       = (data['name']        ?? '—').toString();
            final gmail      = (data['gmail']        ?? data['email'] ?? '—').toString();
            final adminId    = (data['adminId']      ?? data['staffId'] ?? '—').toString();
            final dept       = (data['department']   ?? '—').toString();
            final phone      = (data['phone']        ?? data['mobile'] ?? '—').toString();
            final experience = (data['experience']   ?? '—').toString();
            final joinedYear = (data['joinedYear']   ?? data['joined'] ?? '—').toString();
            final role       = (data['role']         ?? 'admin').toString().toUpperCase();

            return Column(
              children: [
                Text('Profile',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                    .animate()
                    .fadeIn(),
                const SizedBox(height: 24),

                // Avatar
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.greenGradient,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      size: 44, color: Colors.white),
                ).animate().fadeIn(delay: 100.ms).scale(
                    begin: const Offset(0.7, 0.7),
                    curve: Curves.easeOutBack),

                const SizedBox(height: 12),
                Text(name,
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                    .animate().fadeIn(delay: 200.ms),
                Text(role,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        letterSpacing: 1.4,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600))
                    .animate().fadeIn(delay: 250.ms),

                const SizedBox(height: 28),

                // Info card
                GlassCard(
                  child: Column(
                    children: [
                      _InfoRow(Icons.email_outlined,              'Gmail',       gmail),
                      const Divider(color: Colors.white12, height: 20),
                      _InfoRow(Icons.badge_outlined,              'Admin ID',    adminId),
                      const Divider(color: Colors.white12, height: 20),
                      _InfoRow(Icons.apartment_rounded,           'Department',  dept),
                      const Divider(color: Colors.white12, height: 20),
                      _InfoRow(Icons.phone_outlined,              'Phone',       phone),
                      const Divider(color: Colors.white12, height: 20),
                      _InfoRow(Icons.work_outline_rounded,        'Experience',  experience),
                      const Divider(color: Colors.white12, height: 20),
                      _InfoRow(Icons.calendar_today_outlined,     'Joined Year', joinedYear),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 28),

                // Logout button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppColors.danger.withValues(alpha: 0.6),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.logout_rounded,
                        color: AppColors.danger, size: 20),
                    label: Text('Logout',
                        style: GoogleFonts.poppins(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600)),
                    onPressed: () => _logout(context),
                  ),
                ).animate().fadeIn(delay: 400.ms),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.success, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.textSecondary)),
        const Spacer(),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white)),
        ),
      ],
    );
  }
}
