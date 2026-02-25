import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notification_service.dart';

/// ScreenMonitorService \u2014 Flutter-side controller for the native MonitoringService.
///
/// All screen detection and timer logic live in the native Android
/// MonitoringService (ForegroundService.kt).  This class simply:
///   1. Requests notification permission (Android 13+).
///   2. Calls startMonitoring / stopMonitoring on the native service
///      via MethodChannel.
///   3. Exposes [isMonitoring] so the UI can query state.
class ScreenMonitorService {
  static final ScreenMonitorService _instance =
      ScreenMonitorService._internal();
  factory ScreenMonitorService() => _instance;
  ScreenMonitorService._internal();

  static const _channel =
      MethodChannel('com.smartclassroom.smart_classroom/monitoring');

  bool _isMonitoring = false;

  /// Start the native foreground MonitoringService.
  Future<bool> startMonitoring(String studentId, String studentName) async {
    if (_isMonitoring) {
      debugPrint('[Monitor] Already running');
      return true;
    }

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
  Future<void> updateTimetableStatus({required bool active}) async {
    try {
      await _channel.invokeMethod('updateTimetableStatus', {'active': active});
      debugPrint('[Monitor] Timetable status pushed: monitoringActive=$active');
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

