import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../role_select/role_select_screen.dart';
import '../../auth/admin_auth_service.dart';
import '../admin_profile_service.dart';

class AdminProfileScreen extends StatelessWidget {
  final Map<String, dynamic> adminData;
  const AdminProfileScreen({super.key, required this.adminData});

  String get _email => (adminData['gmail'] ?? adminData['email'] ?? '').toString().trim().toLowerCase();

  Future<void> _logout(BuildContext context) async {
    await AdminAuthService.signOut();
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
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
      child: SafeArea(
        child: StreamBuilder<Map<String, dynamic>>(
          stream: AdminProfileService.streamProfile(_email),
          builder: (context, snapshot) {
            final data = snapshot.data ?? adminData;
            final name = data['name'] ?? '—';
            final email = data['email'] ?? '—';
            final department = data['department'] ?? '—';
            final phone = data['phone'] ?? '—';
            final experience = data['experience']?.toString() ?? '—';
            final joinedYear = data['joinedYear']?.toString() ?? '—';
            final role = (data['role'] ?? 'admin').toString().toUpperCase();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
              child: Column(
                children: [
                  Text('Admin Profile',
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary))
                      .animate().fadeIn(),
                  const SizedBox(height: 24),
                  // Avatar
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppGradients.greenGradient,
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 8)),
                      ],
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded,
                        size: 56, color: Colors.white),
                  ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.85, 0.85)),
                  const SizedBox(height: 14),
                  Text(name,
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                      textAlign: TextAlign.center)
                      .animate().fadeIn(delay: 150.ms),
                  Text(role,
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          letterSpacing: 1.4,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600))
                      .animate().fadeIn(delay: 180.ms),
                  const SizedBox(height: 28),
                  // Cards grid
                  _buildGrid([
                    _CardData('Name', name, Icons.person_rounded,
                        const LinearGradient(colors: [Color(0xFF6A5ACD), Color(0xFF4535C1)])),
                    _CardData('Email', email, Icons.email_rounded,
                        const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)])),
                    _CardData('Department', department, Icons.apartment_rounded,
                        const LinearGradient(colors: [Color(0xFFFF9A3C), Color(0xFFE07B00)])),
                    _CardData('Phone', phone, Icons.phone_rounded,
                        const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF00897B)])),
                    _CardData('Experience', '$experience Yrs', Icons.work_rounded,
                        const LinearGradient(colors: [Color(0xFFE84545), Color(0xFFB71C1C)])),
                    _CardData('Joined Year', joinedYear, Icons.calendar_today_rounded,
                        const LinearGradient(colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)])),
                    _CardData('Role', role, Icons.admin_panel_settings_rounded,
                        const LinearGradient(colors: [Color(0xFF8E24AA), Color(0xFF6A1B9A)])),
                    _CardData('Status', 'Active', Icons.verified_rounded,
                        const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF1B5E20)])),
                  ]),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.danger, Color(0xFFFF8A80)]),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.danger.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout_rounded, color: Colors.white),
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
                  ).animate().fadeIn(delay: 500.ms),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(List<_CardData> cards) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, i) {
        final c = cards[i];
        return _InfoCard(data: c)
            .animate()
            .fadeIn(delay: Duration(milliseconds: 220 + i * 60))
            .slideY(begin: 0.12, end: 0);
      },
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
            right: -16, bottom: -16,
            child: Icon(data.icon, size: 76,
                color: Colors.white.withValues(alpha: 0.1)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(data.icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(data.label,
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.7))),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(data.value,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
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
