import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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

  /// Save violation document to Firestore violations collection.
  /// Then send push notification directly to admin device.
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
      debugPrint('[Monitor] ✅ Violation saved: student=$_studentName period=$period seconds=$secondsUsed');

      // Get admin FCM token and send notification
      final adminToken = await _getAdminFcmToken();
      if (adminToken != null && adminToken.isNotEmpty) {
        debugPrint('[Monitor] Admin FCM Token retrieved: ${adminToken.substring(0, 20)}...');
        await _sendPushNotification(
          token: adminToken,
          title: '🔔 Violation Detected!',
          body: '$_studentName - $period - ${secondsUsed}s phone usage',
        );
      } else {
        debugPrint('[Monitor] ⚠️ Admin FCM Token not found or empty');
      }
    } catch (e) {
      debugPrint('[Monitor] ❌ Failed to save violation: $e');
    }
  }

  /// Retrieve the admin device FCM token from Firestore admins collection.
  Future<String?> _getAdminFcmToken() async {
    try {
      debugPrint('[Monitor] Fetching admin FCM token from Firestore...');
      
      final snapshot = await FirebaseFirestore.instance
          .collection('admins')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('[Monitor] No admin documents found in Firestore');
        return null;
      }

      debugPrint('[Monitor] Found ${snapshot.docs.length} admin document(s)');

      // Find first admin with a valid fcmToken
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final token = data['fcmToken'] as String?;
        
        if (token != null && token.isNotEmpty) {
          debugPrint('[Monitor] ✅ Admin FCM Token found');
          return token;
        }
      }

      debugPrint('[Monitor] ❌ No admin with valid fcmToken found');
      return null;
    } catch (e) {
      debugPrint('[Monitor] ❌ Error retrieving admin FCM token: $e');
      return null;
    }
  }

  /// Send push notification to admin device via backend server.
  Future<void> _sendPushNotification({
    required String token,
    required String title,
    required String body,
  }) async {
    if (token.isEmpty) {
      debugPrint('[FCM] ❌ Token is empty, skipping send');
      return;
    }

    debugPrint('[FCM] 📤 Sending notification to admin...');
    debugPrint('[FCM] Title: $title');
    debugPrint('[FCM] Body: $body');

    // Backend endpoint to send notification via Render server
    const backendUrl =
      'https://smartclassroommontoring-system.onrender.com/send-notification';

    final payload = {
      'fcmToken': token,
      'title': title,
      'body': body,
      'data': {
        'type': 'violation',
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    try {
      debugPrint('[FCM] Making HTTP POST request to backend...');
      
      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      debugPrint('[FCM] Response Status: ${response.statusCode}');
      debugPrint('[FCM] Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          debugPrint('[FCM] ✅ Push notification sent successfully!');
          debugPrint('[FCM] Message ID: ${responseData['messageId']}');
        } else {
          debugPrint('[FCM] ❌ Backend returned error: ${responseData['error']}');
        }
      } else {
        debugPrint('[FCM] ❌ Failed to send notification. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] ❌ Exception while sending push notification: $e');
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

