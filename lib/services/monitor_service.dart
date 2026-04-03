import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'alert_delivery_service.dart';
import 'live_monitoring_service.dart';
import 'notification_service.dart';

/// ScreenMonitorService — Flutter-side controller for the native MonitoringService.
class ScreenMonitorService {
  static final ScreenMonitorService _instance =
      ScreenMonitorService._internal();
  factory ScreenMonitorService() => _instance;
  ScreenMonitorService._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel(
    'com.smartclassroom.smart_classroom/monitoring',
  );

  bool _isMonitoring = false;

  String _studentId = '';
  String _studentName = '';
  String _regNo = '';

  final LiveMonitoringService _liveMonitor = LiveMonitoringService();
  final AlertDeliveryService _alertDeliveryService =
      AlertDeliveryService.instance;

  /// Fetch admin phone number from Firestore.
  /// Reads from `admins` collection → `phone` field (as shown in Firebase).
  /// Fallback: also tries `monitoring_settings/global` → `adminPhone`.
  Future<String> _fetchAdminPhone() async {
    // ── Primary: read from admins collection (phone field) ──────────────────
    try {
      final adminsSnap = await FirebaseFirestore.instance
          .collection('admins')
          .limit(5)
          .get();

      for (final doc in adminsSnap.docs) {
        final phone = (doc.data()['phone'] ?? '').toString().trim();
        if (phone.isNotEmpty) {
          // Ensure number starts with + for international format
          final formatted = phone.startsWith('+') ? phone : '+91$phone';
          debugPrint('[Monitor] Admin phone found in admins collection: $formatted');
          return formatted;
        }
      }
    } catch (e) {
      debugPrint('[Monitor] admins collection phone fetch failed: $e');
    }

    // ── Fallback: monitoring_settings/global → adminPhone ────────────────────
    try {
      final globalDoc = await FirebaseFirestore.instance
          .collection('monitoring_settings')
          .doc('global')
          .get();

      final phone = (globalDoc.data()?['adminPhone'] ?? '').toString().trim();
      if (phone.isNotEmpty) {
        final formatted = phone.startsWith('+') ? phone : '+91$phone';
        debugPrint('[Monitor] Admin phone found in monitoring_settings: $formatted');
        return formatted;
      }
    } catch (e) {
      debugPrint('[Monitor] monitoring_settings phone fetch failed: $e');
    }

    debugPrint('[Monitor] ⚠️ No admin phone found in any collection');
    return '';
  }

  /// Handle calls FROM native → Flutter
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onViolation') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final secondsUsed = (args['secondsUsed'] as num?)?.toInt() ?? 20;
      final period = (args['period'] as String?) ?? 'Unknown';

      if (_liveMonitor.violationSentThisSession) {
        debugPrint('[Monitor] Duplicate violation suppressed for this session');
        return;
      }

      await _saveViolationToFirestore(secondsUsed: secondsUsed, period: period);
      _liveMonitor.markViolationSent();
    } else if (call.method == 'onLiveUpdate') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final currentApp = (args['currentApp'] as String?) ?? '';
      final screenTime = (args['screenTime'] as num?)?.toInt() ?? 0;
      final period = (args['period'] as String?) ?? '';
      final status = (args['status'] as String?) ?? 'active';
      final mode = (args['mode'] as String?) ?? 'active';

      _liveMonitor.updateCurrentApp(currentApp);
      _liveMonitor.updateScreenTime(screenTime);
      _liveMonitor.updateCurrentPeriod(period);
      _liveMonitor.updateStatus(status);
      _liveMonitor.updateMode(mode);
    }
  }

  /// Save violation to Firestore + trigger alert delivery.
  Future<void> _saveViolationToFirestore({
    required int secondsUsed,
    required String period,
  }) async {
    try {
      final authenticatedUid = FirebaseAuth.instance.currentUser?.uid;
      final violationOwnerId =
          (authenticatedUid != null && authenticatedUid.isNotEmpty)
          ? authenticatedUid
          : _studentId;

      final violationRef =
          FirebaseFirestore.instance.collection('violations').doc();

      await violationRef.set({
        'studentUID': violationOwnerId,
        'studentName': _studentName,
        'regNo': _regNo,
        'secondsUsed': secondsUsed,
        'period': period,
        'violationType': 'phone_usage',
        'alertTriggered': false,
        'name': _studentName,
        'type': 'phone_usage',
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '[Monitor] ✅ Violation saved: student=$_studentName period=$period seconds=$secondsUsed',
      );

      await _alertDeliveryService.handleViolationAlert(
        violationId: violationRef.id,
        studentUID: violationOwnerId,
        studentName: _studentName,
        regNo: _regNo,
        secondsUsed: secondsUsed,
      );
    } catch (e) {
      debugPrint('[Monitor] ❌ Failed to save violation: $e');
    }
  }

  /// Start the native foreground MonitoringService.
  Future<bool> startMonitoring(
    String studentId,
    String studentName, {
    String regNo = '',
  }) async {
    if (_isMonitoring) {
      debugPrint('[Monitor] Already running');
      return true;
    }

    _studentId = studentId;
    _studentName = studentName;
    _regNo = regNo;

    await NotificationService().initialize();
    await NotificationService().requestPermissions();

    try {
      final result = await _channel.invokeMethod<bool>('startMonitoring');
      _isMonitoring = result ?? false;
      debugPrint('[Monitor] Native service started: $_isMonitoring');

      if (_isMonitoring) {
        // ── Fetch admin phone & push to native (SMS works offline) ────────────
        try {
          final adminPhone = await _fetchAdminPhone();
          if (adminPhone.isNotEmpty) {
            await _channel.invokeMethod('setAdminPhone', {'phone': adminPhone});
            debugPrint('[Monitor] ✅ Admin phone pushed to native: $adminPhone');
          } else {
            debugPrint('[Monitor] ⚠️ Admin phone empty — SMS offline alerts disabled');
          }
        } catch (e) {
          debugPrint('[Monitor] Failed to push adminPhone to native: $e');
        }

        final uid = FirebaseAuth.instance.currentUser?.uid ?? studentId;
        _liveMonitor.start(
          studentUID: uid,
          studentName: studentName,
          regNo: regNo,
        );
      }

      return _isMonitoring;
    } on PlatformException catch (e) {
      debugPrint('[Monitor] Failed to start native service: ${e.message}');
      return false;
    }
  }

  /// Stop the native foreground MonitoringService.
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    try {
      await _channel.invokeMethod<bool>('stopMonitoring');
      _isMonitoring = false;
      await _liveMonitor.stop();
      debugPrint('[Monitor] Native service stopped');
    } on PlatformException catch (e) {
      debugPrint('[Monitor] Failed to stop native service: ${e.message}');
    }
  }

  /// Query the native service to check if monitoring is active.
  Future<bool> checkIsRunning() async {
    try {
      final running = await _channel.invokeMethod<bool>('isMonitoring');
      _isMonitoring = running ?? false;
    } on PlatformException {
      _isMonitoring = false;
    }
    return _isMonitoring;
  }

  /// Admin master switch — enables or disables monitoring globally.
  Future<void> setAdminMonitoring(bool enabled) async {
    try {
      await _channel.invokeMethod('setAdminMonitoring', {'enabled': enabled});
    } on PlatformException catch (e) {
      debugPrint('[Monitor] setAdminMonitoring native call failed: ${e.message}');
    }
    try {
      await FirebaseFirestore.instance
          .collection('monitoring_settings')
          .doc('global')
          .set({'monitoringEnabled': enabled}, SetOptions(merge: true));
      debugPrint('[Monitor] Admin monitoring switch set to: $enabled');
    } catch (e) {
      debugPrint('[Monitor] Failed to write monitoring_settings: $e');
    }
  }

  /// Check Usage Access permission.
  Future<bool> hasUsagePermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the Android Usage Access settings screen.
  Future<void> requestUsagePermission() async {
    try {
      await _channel.invokeMethod('requestUsagePermission');
    } on PlatformException catch (e) {
      debugPrint('[Monitor] Could not open usage settings: ${e.message}');
    }
  }

  /// Push timetable monitoring state to the native service.
  Future<void> updateTimetableStatus({
    required bool active,
    String period = '',
  }) async {
    try {
      await _channel.invokeMethod('updateTimetableStatus', {
        'active': active,
        'period': period,
      });
      debugPrint(
        '[Monitor] Timetable status pushed: monitoringActive=$active period=$period',
      );
    } on PlatformException catch (e) {
      debugPrint('[Monitor] updateTimetableStatus failed: ${e.message}');
    }
  }

  /// Push debug info to native service notification.
  Future<void> pushDebugInfo(String info) async {
    try {
      await _channel.invokeMethod('updateTimetableDebug', {'info': info});
    } on PlatformException catch (_) {}
  }

  bool get isMonitoring => _isMonitoring;
}
