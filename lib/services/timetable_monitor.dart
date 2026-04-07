import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'monitor_service.dart';

/// TimetableMonitor — Dart-side timetable polling service.
///
/// Rule (from Firestore):
///   monitoring: true  → class time  → monitoring ON
///   monitoring: false → break time  → monitoring OFF
///
/// Every 15 seconds it:
///   1. Fetches today's period docs from Firestore
///      timetables → {studentClass} → {dayName} (sub-collection)
///   2. If ANY document has monitoring == true → monitoringActive = true
///   3. Pushes the result to the native MonitoringService via MethodChannel.
class TimetableMonitor {
  static final TimetableMonitor _instance = TimetableMonitor._internal();
  factory TimetableMonitor() => _instance;
  TimetableMonitor._internal();

  static const Duration refreshInterval = Duration(seconds: 15);
  static const String _topCollection = 'timetables';

  final _monitor = ScreenMonitorService();
  final _db = FirebaseFirestore.instance;

  Timer? _timer;
  bool _running = false;

  // Day-name map: Dart weekday int (1=Mon … 7=Sun)
  static const _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  /// [candidates] = list of possible class IDs from the student doc
  /// (e.g. ['CSE_AI_2025', '2024-2028']). Tries each one, then auto-discovers.
  void start(List<String> candidates) {
    if (_running) return;
    _running = true;
    debugPrint('[Timetable] Starting. candidates=$candidates');

    _checkAndPush(candidates);
    _timer = Timer.periodic(refreshInterval, (_) => _checkAndPush(candidates));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    await _monitor.updateTimetableStatus(active: false);
    debugPrint('[Timetable] Stopped');
  }

  // ── Core logic ────────────────────────────────────────────────────────

  Future<void> _checkAndPush(List<String> candidates) async {
    final result = await _isMonitoringActive(candidates);
    await _monitor.updateTimetableStatus(
      active: result.active,
      period: result.periodName,
    );
    await _monitor.pushDebugInfo(result.debugMsg);
    debugPrint('[Timetable] pushed: active=${result.active}, period=${result.periodName}, debug=${result.debugMsg}');
  }

  Future<_TimetableResult> _isMonitoringActive(List<String> candidates) async {
    final dayName  = _currentDayName();       // e.g. "Wednesday"
    final lowerDay = dayName.toLowerCase();   // e.g. "wednesday"

    // ── Step 1: try each candidate class the student doc provides ────────
    for (final cls in candidates) {
      final r = await _queryClass(cls, dayName, lowerDay);
      if (r != null) return r;
    }

    // ── Step 2: auto-discover — scan every document in /timetables/ ──────
    // This covers the case where the student's field names don't match the
    // timetable document IDs (e.g. batch='2024-2028' but timetable='CSE_AI_2025').
    debugPrint('[Timetable] Candidates $candidates had 0 docs — auto-discovering...');
    try {
      final allClasses = await _db.collection(_topCollection).get();
      for (final classDoc in allClasses.docs) {
        if (candidates.contains(classDoc.id)) continue; // already tried
        final r = await _queryClass(classDoc.id, dayName, lowerDay);
        if (r != null) return r;
      }
    } catch (e) {
      debugPrint('[Timetable] Discovery error: $e');
    }

    final tried = candidates.join(',');
    return _TimetableResult(false, 'no docs in any class ($tried+all)');
  }

  /// Try one class ID. Returns a result if docs were found, null if 0 docs.
  Future<_TimetableResult?> _queryClass(
      String cls, String dayName, String lowerDay) async {
    try {
      // Try title-case day name first, then lowercase
      var snap = await _db
          .collection(_topCollection)
          .doc(cls)
          .collection(dayName)
          .get();

      if (snap.docs.isEmpty && dayName != lowerDay) {
        snap = await _db
            .collection(_topCollection)
            .doc(cls)
            .collection(lowerDay)
            .get();
      }

      if (snap.docs.isEmpty) {
        debugPrint('[Timetable] $cls/$lowerDay → 0 docs');
        return null; // signal: try next candidate
      }

      debugPrint('[Timetable] $cls/$lowerDay → ${snap.docs.length} docs');

      // Get current time in minutes from midnight
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;
      debugPrint('[Timetable] currentTime=${now.hour}:${now.minute} ($currentMinutes min)');

      for (final doc in snap.docs) {
        final data = doc.data();
        if (!data.containsKey('monitoring') && data.containsKey('montoring')) {
          debugPrint('[Timetable] ⚠️ Typo field found in ${doc.id}: montoring. Please migrate to monitoring.');
        }
        final raw = data['monitoring'];
        final monitoring = (raw == true || raw == 'true');
        final startTime = (data['startTime'] as num?)?.toInt() ?? 0;
        final endTime   = (data['endTime']   as num?)?.toInt() ?? 0;

        // Check if current time falls within this period
        final inRange = currentMinutes >= startTime && currentMinutes < endTime;

        debugPrint('[Timetable] ${doc.id}: monitoring=$monitoring '  
            'start=$startTime end=$endTime inRange=$inRange');

        if (inRange && monitoring) {
          return _TimetableResult(
            true,
            'CLASS:$cls/${doc.id} ($startTime-$endTime)',
            periodName: doc.id,
          );
        }
        if (inRange && !monitoring) {
          return _TimetableResult(
            false,
            'BREAK:$cls/${doc.id} ($startTime-$endTime)',
            periodName: doc.id,
          );
        }
      }

      // No period matched current time → treat as break / no class
      return _TimetableResult(false, '$cls/$lowerDay:no active period at $currentMinutes min');
    } catch (e) {
      debugPrint('[Timetable] Error querying $cls: $e');
      return null; // treat as 0 docs, try next
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _currentDayName() {
    final now = DateTime.now();
    return _dayNames[now.weekday] ?? 'Monday';
  }

  bool get isRunning => _running;
}

/// Holds both the boolean result and a debug message for the notification.
class _TimetableResult {
  final bool active;
  final String debugMsg;
  final String periodName;   // e.g. "peroid 3" — the Firestore doc ID
  const _TimetableResult(this.active, this.debugMsg, {this.periodName = ''});
}
