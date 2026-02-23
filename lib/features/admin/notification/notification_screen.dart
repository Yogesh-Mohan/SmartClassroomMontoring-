import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _msgCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notification sent successfully!',
            style: GoogleFonts.poppins()),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static const _logs = [
    _Log('Low Attendance Alert sent to Juan Santos', '2 days ago',
        AppColors.danger),
    _Log('Broadcast: Mid-term exam reminder', '3 days ago', AppColors.info),
    _Log('Low Attendance Alert sent to Carlos Ramos', '4 days ago',
        AppColors.danger),
    _Log('Broadcast: Holiday announcement', '1 week ago', AppColors.success),
    _Log('Low Attendance Alert sent to Pedro Reyes', '1 week ago',
        AppColors.warning),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text('Notifications',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white))
                .animate()
                .fadeIn(),
          ),
          const SizedBox(height: 16),
          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.5))),
              dividerColor: Colors.transparent,
              labelColor: AppColors.success,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle:
                  GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Send Alert'),
                Tab(text: 'History'),
              ],
            ),
          ).animate().fadeIn(delay: 100.ms),

          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_sendTab(), _historyTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send Broadcast',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: 4,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: GoogleFonts.poppins(
                          color: AppColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded,
                            size: 18, color: Colors.white),
                    label: Text(
                        _sending ? 'Sending...' : 'Send to All Students',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    onPressed: _sending ? null : _send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _logs.length,
      itemBuilder: (_, i) {
        final log = _logs[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            borderRadius: 14,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(
                    color: log.color, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.message,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.white)),
                      Text(log.time,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: 60 * i)),
        );
      },
    );
  }
}

class _Log {
  final String message;
  final String time;
  final Color color;
  const _Log(this.message, this.time, this.color);
}
