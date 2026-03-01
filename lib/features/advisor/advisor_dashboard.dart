import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import 'pending_certificates_screen.dart';

class AdvisorDashboard extends StatelessWidget {
  final Map<String, dynamic> advisorData;
  const AdvisorDashboard({super.key, required this.advisorData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientStart,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user_rounded,
                      size: 64, color: Colors.white),
                  const SizedBox(height: 14),
                  Text('Advisor Dashboard',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('Review pending certificates and approve credits.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PendingCertificatesScreen(
                          advisorData: advisorData,
                        ),
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    icon: const Icon(Icons.pending_actions_rounded,
                        color: Colors.white),
                    label: Text('Open Pending Certificates',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
