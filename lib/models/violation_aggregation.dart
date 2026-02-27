import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class for aggregated violation data
class ViolationAggregation {
  final int count;
  final DateTime? firstViolationTime;
  final DateTime? lastViolationTime;
  final int totalSecondsUsed;

  ViolationAggregation({
    this.count = 0,
    this.firstViolationTime,
    this.lastViolationTime,
    this.totalSecondsUsed = 0,
  });

  /// Creates aggregation from list of violation documents
  factory ViolationAggregation.fromDocuments(List<DocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return ViolationAggregation();
    }

    DateTime? firstTime;
    DateTime? lastTime;
    int totalSeconds = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
      final seconds = data['secondsUsed'] as int? ?? 0;

      totalSeconds += seconds;

      if (timestamp != null) {
        if (firstTime == null || timestamp.isBefore(firstTime)) {
          firstTime = timestamp;
        }
        if (lastTime == null || timestamp.isAfter(lastTime)) {
          lastTime = timestamp;
        }
      }
    }

    return ViolationAggregation(
      count: docs.length,
      firstViolationTime: firstTime,
      lastViolationTime: lastTime,
      totalSecondsUsed: totalSeconds,
    );
  }

  /// Returns average seconds per violation
  double get averageSecondsPerViolation {
    if (count == 0) return 0.0;
    return totalSecondsUsed / count;
  }

  /// Formats total seconds to readable duration (e.g., "5m 23s")
  String get formattedTotalDuration {
    if (totalSecondsUsed < 60) {
      return '${totalSecondsUsed}s';
    }
    
    final minutes = totalSecondsUsed ~/ 60;
    final seconds = totalSecondsUsed % 60;
    
    if (minutes < 60) {
      return '${minutes}m ${seconds}s';
    }
    
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }

  @override
  String toString() {
    return 'ViolationAggregation(count: $count, totalTime: $formattedTotalDuration)';
  }
}

/// Model for daily violation summary (for streak calculation)
class DailyViolationSummary {
  final DateTime date;
  final int violationCount;
  final bool hasViolations;

  DailyViolationSummary({
    required this.date,
    required this.violationCount,
  }) : hasViolations = violationCount > 0;

  @override
  String toString() {
    return 'DailyViolationSummary(date: ${date.toString()}, count: $violationCount)';
  }
}
