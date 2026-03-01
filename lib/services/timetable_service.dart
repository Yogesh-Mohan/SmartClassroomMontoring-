import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/period_model.dart';

/// A container for the separated morning and afternoon schedules
class DailySchedule {
  final List<Period> morning;
  final List<Period> afternoon;

  /// The detected lunch break start time (from Firestore break period or default 1 PM)
  final TimeOfDay lunchBreakTime;

  DailySchedule({
    required this.morning,
    required this.afternoon,
    this.lunchBreakTime = const TimeOfDay(hour: 13, minute: 0),
  });

  bool get isEmpty => morning.isEmpty && afternoon.isEmpty;
}

/// Service for fetching and processing student timetables from Firestore
class TimetableService {
  final FirebaseFirestore _firestore;

  TimetableService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetches the schedule for the current day and splits it into morning/afternoon
  ///
  /// [classId] is the identifier for the student's class (e.g., "CSE-A").
  /// [lunchStartTime] is the time when afternoon periods begin (defaults to 1 PM).
  Future<DailySchedule> getDailySchedule({
    required String classId,
    List<String> classCandidates = const [],
    TimeOfDay lunchStartTime = const TimeOfDay(hour: 13, minute: 0),
  }) async {
    final today = _getTodayWeekday();
    final dayCandidates = _dayCandidates(today);
    final morningPeriods = <Period>[];
    final afternoonPeriods = <Period>[];
    final classIds = <String>{
      if (classId.trim().isNotEmpty) classId.trim(),
      ...classCandidates.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
    }.toList();

    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;

      for (final cls in classIds) {
        for (final day in dayCandidates) {
          final result = await _firestore
              .collection('timetables')
              .doc(cls)
              .collection(day)
              .get();
          if (result.docs.isNotEmpty) {
            snapshot = result;
            break;
          }
        }
        if (snapshot != null) break;
      }

      if (snapshot == null || snapshot.docs.isEmpty) {
        final allClasses = await _firestore.collection('timetables').get();
        for (final classDoc in allClasses.docs) {
          for (final day in dayCandidates) {
            final result = await _firestore
                .collection('timetables')
                .doc(classDoc.id)
                .collection(day)
                .get();
            if (result.docs.isNotEmpty) {
              snapshot = result;
              break;
            }
          }
          if (snapshot != null) break;
        }
      }

      if (snapshot == null || snapshot.docs.isEmpty) {
        return DailySchedule(morning: [], afternoon: []);
      }

      // Fetch ALL periods (including breaks) to detect the actual lunch break time
      final allPeriods = snapshot.docs
          .map((doc) => Period.fromFirestore(doc))
          .toList()
        ..sort((a, b) {
          final aMin = (a.startTime.hour * 60) + a.startTime.minute;
          final bMin = (b.startTime.hour * 60) + b.startTime.minute;
          return aMin.compareTo(bMin);
        });

      // Detect actual lunch break: first break period between 11 AM – 2 PM (exclusive)
      TimeOfDay detectedLunch = lunchStartTime;
      for (final period in allPeriods) {
        if (period.isBreak || !period.isMonitoring) {
          final h = period.startTime.hour;
          if (h >= 11 && h < 14) {
            detectedLunch = period.startTime;
            break;
          }
        }
      }

      // Only class (monitoring) periods go into the display list
      final periods = allPeriods
          .where((p) => !p.isBreak && p.isMonitoring)
          .toList();

      final lunchTime = detectedLunch.hour + (detectedLunch.minute / 60.0);
      for (final period in periods) {
        // Convert TimeOfDay to a comparable number (e.g., 13:30 -> 13.5)
        final periodStartTime = period.startTime.hour + (period.startTime.minute / 60.0);

        if (periodStartTime < lunchTime) {
          morningPeriods.add(period);
        } else {
          afternoonPeriods.add(period);
        }
      }

      return DailySchedule(
        morning: morningPeriods,
        afternoon: afternoonPeriods,
        lunchBreakTime: detectedLunch,
      );
    } catch (e) {
      // Handle potential errors like permission issues or network problems
      debugPrint('Error fetching timetable: $e');
      return DailySchedule(morning: [], afternoon: []);
    }
  }

  /// Returns the current day of the week as a lowercase string (e.g., "monday")
  String _getTodayWeekday() {
    final now = DateTime.now();
    switch (now.weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
        return 'sunday';
      default:
        return '';
    }
  }

  List<String> _dayCandidates(String day) {
    if (day.isEmpty) return const [];
    final lower = day.toLowerCase();
    final title = '${lower[0].toUpperCase()}${lower.substring(1)}';
    final upper = lower.toUpperCase();
    return [lower, title, upper];
  }
}
