import 'package:flutter/material.dart';

import 'live_monitoring_screen.dart';

/// Legacy route retained for backward compatibility.
/// This screen now delegates to the real Firestore-backed live monitoring UI.
class MonitoringScreen extends StatelessWidget {
  const MonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LiveMonitoringScreen();
  }
}
