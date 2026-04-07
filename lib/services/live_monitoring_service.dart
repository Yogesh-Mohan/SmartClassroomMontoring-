import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LiveMonitoringService — Pushes real-time student phone activity to Firestore.
///
/// Every [updateInterval] seconds it writes to:
///   live_monitoring/{studentUID}
///
/// It also streams `monitoring_settings/global` → when admin toggles monitoring
/// OFF, this service immediately tells the native service to stop counting and
/// resets screen time to 0 (violation-free).
class LiveMonitoringService {
  static final LiveMonitoringService _instance =
      LiveMonitoringService._internal();
  factory LiveMonitoringService() => _instance;
  LiveMonitoringService._internal();

  // Keep a low-frequency heartbeat so Spark plan write quota is not exhausted.
  static const Duration updateInterval = Duration(minutes: 3);
  static const Duration heartbeatInterval = Duration(minutes: 5);
  static const _channel = MethodChannel(
    'com.smartclassroom.smart_classroom/monitoring',
  );

  final _db = FirebaseFirestore.instance;

  Timer? _timer;
  bool _running = false;
  DateTime? _lastPushAt;
  DateTime? _lastRealtimeSyncAt;
  Map<String, Object?>? _lastPushedState;
  static const Duration realtimeSyncMinGap = Duration(seconds: 4);

  // Student identity
  String _studentUID = '';
  String _studentName = '';
  String _regNo = '';

  // Live state — updated externally by the monitor/timetable services
  String _currentPeriod = '';
  String _currentApp = '';
  int _screenTime = 0;
  String _status = 'active'; // active | idle | offline
  String _mode = 'active'; // active | passive | sleep

  // Violation dedup — persists by day + period to avoid duplicates after app restart.
  bool _violationSentThisSession = false;
  String _lastViolationPeriod = '';

  // Admin master switch
  StreamSubscription<DocumentSnapshot>? _adminSettingsListener;
  bool _adminMonitoringEnabled = true;

  // ── Start / Stop ──────────────────────────────────────────────────────────

  /// Start pushing live data to Firestore + listen to admin master switch.
  void start({
    required String studentUID,
    required String studentName,
    required String regNo,
  }) {
    if (_running) return;
    _studentUID = studentUID;
    _studentName = studentName;
    _regNo = regNo;
    _running = true;
    _status = 'active';
    _lastRealtimeSyncAt = null;
    debugPrint('[LiveMonitor] Starting for $_studentName ($_studentUID)');

    // Listen to admin master switch changes in real-time
    _startAdminSettingsListener();

    // Initial push
    _pushToFirestore(force: true);
    _timer = Timer.periodic(updateInterval, (_) => _pushToFirestore());
  }

  /// Stop pushing live data and set status to offline.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _status = 'offline';
    _lastRealtimeSyncAt = null;
    _adminSettingsListener?.cancel();
    _adminSettingsListener = null;
    await _pushToFirestore(force: true);
    debugPrint('[LiveMonitor] Stopped');
  }

  // ── Admin Master Switch Listener ──────────────────────────────────────────

  /// Listens to `monitoring_settings/global` — when admin toggles the switch,
  /// this listener fires and tells the native service to pause/resume.
  void _startAdminSettingsListener() {
    _adminSettingsListener?.cancel();
    _adminSettingsListener = _db
        .collection('monitoring_settings')
        .doc('global')
        .snapshots()
        .listen((doc) async {
          if (!doc.exists) return;
          final enabled = (doc.data()?['monitoringEnabled'] as bool?) ?? true;
          if (enabled == _adminMonitoringEnabled) return; // no change

          _adminMonitoringEnabled = enabled;
          debugPrint('[LiveMonitor] Admin switch → monitoringEnabled=$enabled');

          // Tell native service to pause or resume counting
          try {
            await _channel.invokeMethod('setAdminMonitoring', {
              'enabled': enabled,
            });
          } on PlatformException catch (e) {
            debugPrint(
              '[LiveMonitor] Native setAdminMonitoring failed: ${e.message}',
            );
          }

          // If monitoring was paused → clear screen time and notify admin immediately
          if (!enabled) {
            _screenTime = 0;
            _currentApp = '';
            _mode = 'passive';
            _violationSentThisSession = false;
            _lastViolationPeriod = '';
            await _pushToFirestore(force: true); // push zeroed state right now
          } else {
            // Re-enabled: update status to active immediately so students appear active
            // and native service will resume counting from here
            _status = 'active';
            _mode = 'active';
            _violationSentThisSession = false;
            _lastViolationPeriod = '';
            await _pushToFirestore(force: true);
          }
        });
  }

  // ── External setters (called by ScreenMonitorService / native callbacks) ──

  void updateCurrentApp(String appPackage) {
    if (appPackage != _currentApp) {
      _currentApp = appPackage;
      // App changed → reset violation flag for the new usage session
      _violationSentThisSession = false;
      _screenTime = 0;
      _requestRealtimeSync(force: true);
    }
  }

  void updateScreenTime(int seconds) {
    _screenTime = seconds;

    // Push immediately when active usage starts so admin sees 1s, 2s, 3s live.
    if (_status == 'active' && seconds <= 1) {
      _requestRealtimeSync(force: true);
    }

    // While active, refresh backend every 15s to keep admin status accurate.
    if (_status == 'active' && seconds > 0 && seconds % 15 == 0) {
      _requestRealtimeSync();
    }
  }

  void updateCurrentPeriod(String period) {
    if (_currentPeriod != period) {
      _violationSentThisSession = false;
      _lastViolationPeriod = '';
    }
    _currentPeriod = period;
  }

  void updateStatus(String status) {
    if (_status == status) return;
    _status = status;
    _requestRealtimeSync(force: true);
  }

  void updateMode(String mode) {
    if (_mode == mode) return;
    _mode = mode;
    _requestRealtimeSync(force: true);
  }

  /// Returns true if a violation has already been recorded for this session.
  bool get violationSentThisSession => _violationSentThisSession;

  Future<bool> hasViolationForPeriod(String period) async {
    if (_violationSentThisSession && _lastViolationPeriod == period) {
      return true;
    }

    if (_studentUID.isEmpty || period.trim().isEmpty) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dedupKey(period)) ?? false;
  }

  Future<void> markViolationSent(String period) async {
    _violationSentThisSession = true;
    _lastViolationPeriod = period;
    if (_studentUID.isEmpty || period.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dedupKey(period), true);
  }

  String _dedupKey(String period) {
    final now = DateTime.now();
    final day =
        '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
    return 'violation_dedup_${_studentUID}_${period.trim()}_$day';
  }

  /// Reset the violation flag (e.g. when app changes or timer resets).
  void resetViolationFlag() {
    _violationSentThisSession = false;
  }

  bool get isRunning => _running;

  void _requestRealtimeSync({bool force = false}) {
    if (!_running || _studentUID.isEmpty) return;
    final now = DateTime.now();

    if (!force && _lastRealtimeSyncAt != null) {
      final diff = now.difference(_lastRealtimeSyncAt!);
      if (diff < realtimeSyncMinGap) return;
    }

    _lastRealtimeSyncAt = now;
    _fireAndForgetRealtimePush();
  }

  void _fireAndForgetRealtimePush() {
    _pushToFirestore(force: true).catchError((e) {
      debugPrint('[LiveMonitor] Realtime push failed: $e');
    });
  }

  // ── Firestore push ────────────────────────────────────────────────────────

  Future<void> _pushToFirestore({bool force = false}) async {
    if (_studentUID.isEmpty) return;

    final now = DateTime.now();
    final data = <String, Object?>{
      'studentName': _studentName,
      'regNo': _regNo,
      'currentPeriod': _currentPeriod,
      'currentApp': _currentApp,
      'screenTime': _screenTime,
      'status': _status,
      'mode': _mode,
    };

    // Skip writes when nothing changed and heartbeat window has not elapsed.
    final unchanged =
        _lastPushedState != null && _mapEquals(_lastPushedState!, data);
    final withinHeartbeat =
        _lastPushAt != null && now.difference(_lastPushAt!) < heartbeatInterval;
    if (!force && unchanged && withinHeartbeat) {
      return;
    }

    try {
      await _db.collection('live_monitoring').doc(_studentUID).set({
        ...data,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _lastPushAt = now;
      _lastPushedState = Map<String, Object?>.from(data);
    } catch (e) {
      debugPrint('[LiveMonitor] ❌ Firestore push failed: $e');
    }
  }

  bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
