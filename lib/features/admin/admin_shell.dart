import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../services/notification_service.dart';
import '../advisor/pending_certificates_screen.dart';
import 'home/admin_home_screen.dart';
import 'notification/notification_screen.dart';
import 'profile/admin_profile_screen.dart';
import 'violations/violations_screen.dart';

class AdminShell extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminShell({super.key, required this.adminData});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  late final List<Widget> _pages;
  StreamSubscription<QuerySnapshot>? _violationsSubscription;
  Timestamp? _shellStartedAt;

  @override
  void initState() {
    super.initState();
    _pages = [
      AdminHomeScreen(adminData: widget.adminData),
      PendingCertificatesScreen(advisorData: widget.adminData),
      const AdminViolationsScreen(),
      const NotificationScreen(),
      AdminProfileScreen(adminData: widget.adminData),
    ];
    _bootstrapAdminPush();
    _setupFcmTokenRefreshListener();
    _startViolationsListener();
  }

  Future<void> _bootstrapAdminPush() async {
    await NotificationService().initialize();
    await NotificationService().requestPermissions();
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await NotificationService().registerFcmForegroundHandlers();
    await _registerCurrentFcmToken();
  }

  Future<void> _registerCurrentFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) {
        debugPrint('[Admin FCM] Current token unavailable');
        return;
      }
      await _saveFcmTokenToFirestore(token);
    } catch (e) {
      debugPrint('[Admin FCM] Failed to fetch current token: $e');
    }
  }

  /// Listen for FCM token changes and automatically update Firestore.
  /// This fixes the issue where token changes every time admin logs in.
  void _setupFcmTokenRefreshListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('[Admin FCM] Token refreshed: $newToken');
      await _saveFcmTokenToFirestore(newToken);
    });
  }

  /// Listen for NEW violations in real-time and show local notification.
  /// This is independent of Render server / Cloud Functions cold starts.
  void _startViolationsListener() {
    _shellStartedAt = Timestamp.fromDate(DateTime.now());
    _violationsSubscription = FirebaseFirestore.instance
        .collection('violations')
        .where('timestamp', isGreaterThan: _shellStartedAt)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d == null) continue;
          final name    = (d['name']        ?? 'Student').toString();
          final period  = (d['period']      ?? 'Unknown').toString();
          final seconds = (d['secondsUsed'] as num?)?.toInt() ?? 0;
          debugPrint('[AdminShell] 🔔 New violation detected: $name - $period');
          NotificationService().showPushNotification(
            title: '🔔 Violation Detected!',
            body:  '$name - $period - ${seconds}s phone usage',
            data:  {'type': 'violation'},
          );
        }
      }
    }, onError: (e) {
      debugPrint('[AdminShell] Violations listener error: $e');
    });
  }

  /// Save FCM token to Firestore admins/{uid} document.
  Future<void> _saveFcmTokenToFirestore(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('[Admin FCM] Save failed: no current user UID');
        return;
      }
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      debugPrint('[Admin FCM] Token saved to Firestore: admins/$uid');
    } catch (e) {
      debugPrint('[Admin FCM] Save error: $e');
    }
  }

  @override
  void dispose() {
    _violationsSubscription?.cancel();
    super.dispose();
  }

  static const _navItems = [
    _NavItem(Icons.dashboard_rounded,      Icons.dashboard_outlined,       'Dashboard'),
    _NavItem(Icons.insights_rounded,  Icons.insights_outlined,   'Insights'),
    _NavItem(Icons.warning_amber_rounded,  Icons.warning_amber_outlined,   'Violations'),
    _NavItem(Icons.notifications_rounded,  Icons.notifications_outlined,   'Alerts'),
    _NavItem(Icons.person_rounded,         Icons.person_outlined,          'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050520),
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1), width: 1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)
        ],
      ),
      padding: const EdgeInsets.only(bottom: 6, top: 6),
      child: Row(
        children: List.generate(_navItems.length, (i) {
          final item = _navItems[i];
          final selected = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _currentIndex = i),
              child: AnimatedScale(
                scale: selected ? 1.0 : 0.9,
                duration: const Duration(milliseconds: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? item.activeIcon : item.icon,
                      size: 24,
                      color: selected
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: selected ? 20 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData activeIcon;
  final IconData icon;
  final String label;
  const _NavItem(this.activeIcon, this.icon, this.label);
}
