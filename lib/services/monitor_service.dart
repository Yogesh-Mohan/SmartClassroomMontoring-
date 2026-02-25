import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const _channel =
      MethodChannel('com.smartclassroom.smart_classroom/monitoring');

  bool _isMonitoring = false;

  // Student info stored when monitoring starts
  String _studentId   = '';
  String _studentName = '';
  String _regNo       = '';

  /// Handle calls FROM native → Flutter (e.g. violation fired)
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onViolation') {
      final args        = Map<String, dynamic>.from(call.arguments as Map);
      final secondsUsed = (args['secondsUsed'] as num?)?.toInt() ?? 20;
      final period      = (args['period'] as String?) ?? 'Unknown';
      await _saveViolationToFirestore(
        secondsUsed: secondsUsed,
        period: period,
      );
    }
  }

  /// Save violation document to Firestore violations collection
  Future<void> _saveViolationToFirestore({
    required int secondsUsed,
    required String period,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('violations').add({
        'studentUID'  : _studentId,
        'name'        : _studentName,
        'regNo'       : _regNo,
        'secondsUsed' : secondsUsed,
        'period'      : period,
        'timestamp'   : FieldValue.serverTimestamp(),
      });
      debugPrint('[Monitor] Violation saved: student=$_studentName period=$period seconds=$secondsUsed');
    } catch (e) {
      debugPrint('[Monitor] Failed to save violation: $e');
    }
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
    _studentId   = studentId;
    _studentName = studentName;
    _regNo       = regNo;

    // Request Android 13+ notification permission
    await NotificationService().initialize();
    await NotificationService().requestPermissions();

    try {
      final result = await _channel.invokeMethod<bool>('startMonitoring');
      _isMonitoring = result ?? false;
      debugPrint('[Monitor] Native service started: $_isMonitoring');
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
      debugPrint('[Monitor] Timetable status pushed: monitoringActive=$active period=$period');
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

