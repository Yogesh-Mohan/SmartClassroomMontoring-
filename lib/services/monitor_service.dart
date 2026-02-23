import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:screen_state/screen_state.dart';
import 'notification_service.dart';

/// ScreenMonitorService - Monitors screen state and enforces 20-second rule
class ScreenMonitorService {
  static final ScreenMonitorService _instance = ScreenMonitorService._internal();
  factory ScreenMonitorService() => _instance;
  ScreenMonitorService._internal();

  bool _isMonitoring = false;
  
  /// Initialize and start the foreground service with monitoring
  Future<bool> startMonitoring(String studentId, String studentName) async {
    if (_isMonitoring) {
      debugPrint('Monitoring already running');
      return true;
    }

    // Initialize notification service and request permission
    final notifService = NotificationService();
    await notifService.initialize();
    await notifService.requestPermissions();

    // Initialize foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'screen_monitor_channel',
        channelName: 'Screen Monitor Service',
        channelDescription: 'Monitors screen usage for classroom compliance',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000), // 1 second for accurate counting
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    // Start foreground service
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Screen Monitor Active',
      notificationText: 'Monitoring screen usage',
      callback: startScreenMonitorCallback,
    );

    // Send student data to isolate
    FlutterForegroundTask.sendDataToTask({
      'action': 'init',
      'studentId': studentId,
      'studentName': studentName,
    });
    
    _isMonitoring = true;
    debugPrint('Screen monitoring started successfully');
    return true;
  }

  /// Stop the monitoring service
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    await FlutterForegroundTask.stopService();
    _isMonitoring = false;
    debugPrint('Screen monitoring stopped');
  }

  bool get isMonitoring => _isMonitoring;
}

/// Foreground task callback - runs in isolate
@pragma('vm:entry-point')
void startScreenMonitorCallback() {
  FlutterForegroundTask.setTaskHandler(ScreenMonitorTaskHandler());
}

/// Task handler that runs in the isolate
class ScreenMonitorTaskHandler extends TaskHandler {
  final Screen _screenStatePlugin = Screen();
  StreamSubscription<ScreenStateEvent>? _screenSubscription;

  int _elapsedSeconds = 0;

  // Screen is assumed ON when service starts (student just opened the app)
  bool _isScreenOn = true;

  // Grace period: ignore screenOff events fired right at startup (some phones
  // emit a stale screenOff broadcast the moment the listener registers).
  bool _startupGraceActive = true;

  static const int violationThreshold = 20; // seconds

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[Monitor] Task started');

    await NotificationService().initialize();

    // Listen to screen state changes
    _screenSubscription = _screenStatePlugin.screenStateStream.listen(
      _onScreenStateChanged,
      onError: (e) => debugPrint('[Monitor] Stream error: $e'),
    );

    // After 3 seconds, end grace period — safe to trust screenOff events
    Future.delayed(const Duration(seconds: 3), () {
      _startupGraceActive = false;
      debugPrint('[Monitor] Grace period ended – screen state: ${_isScreenOn ? "ON" : "OFF"}');
    });

    debugPrint('[Monitor] Listener ready. Initial state: ON');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called every 1 second
    if (_isScreenOn) {
      _elapsedSeconds++;
      debugPrint('[Monitor] Screen ON: ${_elapsedSeconds}s / ${violationThreshold}s');

      if (_elapsedSeconds >= violationThreshold) {
        _triggerViolation();
      }
    }

    // Keep foreground notification text accurate
    FlutterForegroundTask.updateService(
      notificationTitle: 'Screen Monitor Active',
      notificationText: _isScreenOn
          ? 'Screen ON – monitoring active'
          : 'Screen OFF – monitoring',
    );
  }

  @override
  Future<void> onReceiveData(Object data) async {
    if (data is Map) {
      final action = data['action'];
      if (action == 'init') {
        debugPrint('Student data received: ${data['studentName']}');
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _screenSubscription?.cancel();
    debugPrint('[Monitor] Task destroyed');
  }

  /// Handle screen state events
  void _onScreenStateChanged(ScreenStateEvent event) {
    debugPrint('[Monitor] Screen event: $event | grace=$_startupGraceActive');

    if (event == ScreenStateEvent.screenOn ||
        event == ScreenStateEvent.screenUnlocked) {
      // Screen turned ON or user unlocked — always trust this
      _isScreenOn = true;
      _elapsedSeconds = 0;
      debugPrint('[Monitor] Screen ON/Unlocked → timer reset to 0');
    } else if (event == ScreenStateEvent.screenOff) {
      if (_startupGraceActive) {
        // Ignore stale screenOff fired right at service startup
        debugPrint('[Monitor] screenOff ignored (grace period active)');
        return;
      }
      _isScreenOn = false;
      _elapsedSeconds = 0;
      debugPrint('[Monitor] Screen OFF → timer reset to 0');
    }
  }

  /// Fire violation and reset timer
  void _triggerViolation() {
    debugPrint('[Monitor] VIOLATION – screen ON for ${_elapsedSeconds}s');

    NotificationService().showViolationNotification(
      title: 'RULE BROKEN',
      body: '20 seconds exceeded – Put your phone down!',
      seconds: _elapsedSeconds,
    );

    // Reset and keep monitoring
    _elapsedSeconds = 0;
    debugPrint('[Monitor] Timer reset – continuing monitoring');
  }
}
