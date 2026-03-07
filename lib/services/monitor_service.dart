import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'live_monitoring_service.dart';
import 'notification_service.dart';

/// ScreenMonitorService — Flutter-side controller for the native MonitoringService.
class ScreenMonitorService {
  static final ScreenMonitorService _instance =
      ScreenMonitorService._internal();
  factory ScreenMonitorService() => _instance;
  ScreenMonitorService._internal() {
    // Listen for violation callbacks from the native service
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel(
    'com.smartclassroom.smart_classroom/monitoring',
  );

  bool _isMonitoring = false;

  // Student info stored when monitoring starts
  String _studentId = '';
  String _studentName = '';
  String _regNo = '';

  final LiveMonitoringService _liveMonitor = LiveMonitoringService();

  /// Handle calls FROM native → Flutter (e.g. violation fired, live updates)
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onViolation') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final secondsUsed = (args['secondsUsed'] as num?)?.toInt() ?? 20;
      final period = (args['period'] as String?) ?? 'Unknown';

      // Prevent duplicate violations for the same usage session
      if (_liveMonitor.violationSentThisSession) {
        debugPrint('[Monitor] Duplicate violation suppressed for this session');
        return;
      }

      await _saveViolationToFirestore(secondsUsed: secondsUsed, period: period);
      _liveMonitor.markViolationSent();
    } else if (call.method == 'onLiveUpdate') {
      // Receive live monitoring data from native service
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final currentApp = (args['currentApp'] as String?) ?? '';
      final screenTime = (args['screenTime'] as num?)?.toInt() ?? 0;
      final period = (args['period'] as String?) ?? '';
      final status = (args['status'] as String?) ?? 'active';

      _liveMonitor.updateCurrentApp(currentApp);
      _liveMonitor.updateScreenTime(screenTime);
      _liveMonitor.updateCurrentPeriod(period);
      _liveMonitor.updateStatus(status);
    }
  }

  /// Save violation document to Firestore violations collection.
  /// Then send push notification directly to admin device.
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

      await FirebaseFirestore.instance.collection('violations').add({
        'studentUID': violationOwnerId,
        'name': _studentName,
        'regNo': _regNo,
        'secondsUsed': secondsUsed,
        'period': period,
        'type': 'phone_usage',
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '[Monitor] ✅ Violation saved: student=$_studentName period=$period seconds=$secondsUsed',
      );

      await _notifyAdminsForViolation(secondsUsed: secondsUsed, period: period);
    } catch (e) {
      debugPrint('[Monitor] ❌ Failed to save violation: $e');
    }
  }

  /// Notify all admins about a rule violation.
  Future<void> _notifyAdminsForViolation({
    required int secondsUsed,
    required String period,
  }) async {
    try {
      final sent = await _notifyAdminsViaFunction(
        title: '🔔 Violation Detected!',
        body: '$_studentName - $period - ${secondsUsed}s phone usage',
        data: {
          'studentName': _studentName,
          'period': period,
          'secondsUsed': secondsUsed.toString(),
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'violation',
        },
      );

      if (sent) {
        debugPrint(
          '[Monitor] ✅ Admin notification request sent via Cloud Function',
        );
      }
    } catch (e) {
      debugPrint('[Monitor] ❌ Error while notifying admins: $e');
    }
  }

  /// Request admin fan-out notification via Firebase HTTPS function.
  Future<bool> _notifyAdminsViaFunction({
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    debugPrint('[FCM] 📤 Requesting admin fan-out notification...');

    const backendUrl =
        'https://smartclassroommontoring-system.onrender.com/notify-admins';

    final payload = {'title': title, 'body': body, 'data': data};

    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[FCM] Attempt $attempt/$maxAttempts — POST $backendUrl');

        final response = await http
            .post(
              Uri.parse(backendUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(payload),
            )
            .timeout(const Duration(seconds: 15));

        debugPrint('[FCM] Response Status: ${response.statusCode}');
        debugPrint('[FCM] Response Body: ${response.body}');

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            return true;
          }
          debugPrint('[FCM] ❌ Backend error: ${responseData['error']}');
        }
      } catch (e) {
        debugPrint('[FCM] ❌ Attempt $attempt exception: $e');
      }
    }

    debugPrint('[FCM] ❌ notifyAdmins failed after all attempts.');
    return false;
  }

  /// Start the native foreground MonitoringService.
  /// Pass student identity so violations can be saved with correct data.
  Future<bool> startMonitoring(
    String studentId,
    String studentName, {
    String regNo = '',
  }) async {
    if (_isMonitoring) {
      debugPrint('[Monitor] Already running');
      return true;
    }

    // Store student data for violation saves
    _studentId = studentId;
    _studentName = studentName;
    _regNo = regNo;

    // Request Android 13+ notification permission
    await NotificationService().initialize();
    await NotificationService().requestPermissions();

    try {
      final result = await _channel.invokeMethod<bool>('startMonitoring');
      _isMonitoring = result ?? false;
      debugPrint('[Monitor] Native service started: $_isMonitoring');

      // Start the live monitoring Firestore sync
      if (_isMonitoring) {
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
      // Stop live monitoring → sets status to 'offline' in Firestore
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

  /// Check if the app has been granted Usage Access (PACKAGE_USAGE_STATS).
  /// Required for foreground app detection.
  Future<bool> hasUsagePermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the Android Usage Access settings screen.
  /// The user must manually toggle the permission for this app.
  Future<void> requestUsagePermission() async {
    try {
      await _channel.invokeMethod('requestUsagePermission');
    } on PlatformException catch (e) {
      debugPrint('[Monitor] Could not open usage settings: ${e.message}');
    }
  }

  /// Push the current timetable monitoring state to the native service.
  ///
  /// Called by [TimetableMonitor] every 15 seconds.
  /// [active] = true  → inside a class period with monitoring == true
  /// [active] = false → break time, after hours, or timetable empty
  /// [period] = Firestore doc ID of the current active period (e.g. "peroid 3")
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

  /// Push a short debug message to the native side so it can be shown
  /// in the foreground service notification for diagnostic purposes.
  Future<void> pushDebugInfo(String info) async {
    try {
      await _channel.invokeMethod('updateTimetableDebug', {'info': info});
    } on PlatformException catch (_) {}
  }

  bool get isMonitoring => _isMonitoring;
}
