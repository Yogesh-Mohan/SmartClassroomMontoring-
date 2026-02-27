import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/violation_aggregation.dart';
import '../utils/date_helpers.dart';

/// Service for calculating violation statistics and behavior streaks
class ViolationsStatsService {
  final FirebaseFirestore _firestore;
  
  ViolationsStatsService({FirebaseFirestore? firestore}) 
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Collection reference for violations
  CollectionReference get _violationsCollection => _firestore.collection('violations');

  /// Get count of violations in the current tracking period (previous 11 PM to next 11 PM)
  /// This represents "today's" violations based on 11 PM boundaries
  Future<int> getTodayViolationsCount(String studentUID) async {
    final periodStart = DateHelpers.getCurrentPeriodStart();
    
    final snapshot = await _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(periodStart))
        .get();
    
    return snapshot.docs.length;
  }

  /// Get real-time stream of today's violation count
  Stream<int> streamTodayViolations(String studentUID) {
    final periodStart = DateHelpers.getCurrentPeriodStart();
    
    return _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(periodStart))
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Calculate behavior streak: consecutive days (11 PM blocks) without violations
  /// Returns number of complete days without violations, counting backward from current period
  Future<int> calculateBehaviorStreak(String studentUID) async {
    int streak = 0;
    final now = DateTime.now();
    
    // Check each day going backwards from current period
    for (int daysBack = 0; daysBack < 365; daysBack++) {
      final periodEnd = DateHelpers.getCurrentPeriodEnd().subtract(Duration(days: daysBack));
      final periodStart = periodEnd.subtract(const Duration(days: 1));
      
      // Don't check future periods
      if (periodStart.isAfter(now)) {
        continue;
      }
      
      final violationsInPeriod = await _getViolationsInPeriod(
        studentUID,
        periodStart,
        periodEnd,
      );
      
      if (violationsInPeriod > 0) {
        // Streak broken
        break;
      }
      
      streak++;
    }
    
    return streak;
  }

  /// Get violation count for a specific time period
  Future<int> _getViolationsInPeriod(
    String studentUID,
    DateTime start,
    DateTime end,
  ) async {
    final snapshot = await _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    
    return snapshot.docs.length;
  }

  /// Get detailed violation aggregation for today
  Future<ViolationAggregation> getTodayViolationDetails(String studentUID) async {
    final periodStart = DateHelpers.getCurrentPeriodStart();
    
    final snapshot = await _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(periodStart))
        .orderBy('timestamp', descending: false)
        .get();
    
    return ViolationAggregation.fromDocuments(snapshot.docs);
  }

  /// Get violation count for last N days (using 11 PM boundaries)
  Future<Map<String, int>> getViolationsByDay(String studentUID, int days) async {
    final result = <String, int>{};
    final now = DateTime.now();
    
    for (int i = 0; i < days; i++) {
      final periodEnd = DateHelpers.getCurrentPeriodEnd().subtract(Duration(days: i));
      final periodStart = periodEnd.subtract(const Duration(days: 1));
      
      if (periodStart.isAfter(now)) {
        continue;
      }
      
      final count = await _getViolationsInPeriod(studentUID, periodStart, periodEnd);
      
      // Format: "Feb 28"
      final dateKey = '${_getMonthName(periodEnd.month)} ${periodEnd.day}';
      result[dateKey] = count;
    }
    
    return result;
  }

  /// Get all-time violation count for a student
  Future<int> getTotalViolationsCount(String studentUID) async {
    final snapshot = await _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .get();
    
    return snapshot.docs.length;
  }

  /// Get violations for the current week (Monday to Sunday)
  Future<int> getWeeklyViolationsCount(String studentUID) async {
    final now = DateTime.now();
    
    // Find Monday of current week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day, 0, 0, 0);
    
    final snapshot = await _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .get();
    
    return snapshot.docs.length;
  }

  /// Get daily summaries for streak calculation
  Future<List<DailyViolationSummary>> getDailySummaries(
    String studentUID,
    int daysBack,
  ) async {
    final summaries = <DailyViolationSummary>[];
    final now = DateTime.now();
    
    for (int i = 0; i < daysBack; i++) {
      final periodEnd = DateHelpers.getCurrentPeriodEnd().subtract(Duration(days: i));
      final periodStart = periodEnd.subtract(const Duration(days: 1));
      
      if (periodStart.isAfter(now)) {
        continue;
      }
      
      final count = await _getViolationsInPeriod(studentUID, periodStart, periodEnd);
      
      summaries.add(DailyViolationSummary(
        date: periodEnd,
        violationCount: count,
      ));
    }
    
    return summaries;
  }

  /// Helper to get month abbreviation
  String _getMonthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }

  /// Stream violations for real-time updates (limited to recent violations)
  Stream<List<Map<String, dynamic>>> streamRecentViolations(
    String studentUID, {
    int limit = 10,
  }) {
    return _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return doc.data() as Map<String, dynamic>;
      }).toList();
    });
  }
}
