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

  /// Fetch all violations for a student (single-field query – no composite index needed).
  /// Returns docs sorted oldest→newest so callers can filter by timestamp in Dart.
  Future<List<QueryDocumentSnapshot>> _fetchAllViolations(String studentUID) async {
    final snap = await _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .get();
    final docs = snap.docs.toList();
    // Sort client-side by timestamp ascending
    docs.sort((a, b) {
      final ta = (a.data() as Map<String, dynamic>)['timestamp'];
      final tb = (b.data() as Map<String, dynamic>)['timestamp'];
      if (ta == null && tb == null) return 0;
      if (ta == null) return -1;
      if (tb == null) return 1;
      final dtA = (ta as Timestamp).toDate();
      final dtB = (tb as Timestamp).toDate();
      return dtA.compareTo(dtB);
    });
    return docs;
  }

  /// Get count of violations in the current tracking period (previous 11 PM to next 11 PM)
  /// This represents "today's" violations based on 11 PM boundaries
  Future<int> getTodayViolationsCount(String studentUID) async {
    final periodStart = DateHelpers.getCurrentPeriodStart();
    final all = await _fetchAllViolations(studentUID);
    return all.where((doc) {
      final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
      if (ts == null) return false;
      return (ts as Timestamp).toDate().isAfter(periodStart);
    }).length;
  }

  /// Get real-time stream of today's violation count.
  /// Uses single-field query (no composite index) and filters timestamp in Dart.
  Stream<int> streamTodayViolations(String studentUID) {
    final periodStart = DateHelpers.getCurrentPeriodStart();
    return _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.where((doc) {
        final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
        if (ts == null) return false;
        return (ts as Timestamp).toDate().isAfter(periodStart);
      }).length;
    });
  }

  /// Calculate behavior streak: consecutive days (11 PM blocks) without violations.
  /// Fetches all violations once, then checks each day in Dart.
  Future<int> calculateBehaviorStreak(String studentUID) async {
    final all = await _fetchAllViolations(studentUID);
    int streak = 0;
    final now = DateTime.now();

    for (int daysBack = 0; daysBack < 365; daysBack++) {
      final periodEnd = DateHelpers.getCurrentPeriodEnd().subtract(Duration(days: daysBack));
      final periodStart = periodEnd.subtract(const Duration(days: 1));

      if (periodStart.isAfter(now)) continue;

      final count = _countInPeriod(all, periodStart, periodEnd);
      if (count > 0) break;
      streak++;
    }
    return streak;
  }

  /// Count docs whose timestamp falls in (start, end] — in-memory, no extra queries.
  int _countInPeriod(
    List<QueryDocumentSnapshot> docs,
    DateTime start,
    DateTime end,
  ) {
    return docs.where((doc) {
      final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
      if (ts == null) return false;
      final dt = (ts as Timestamp).toDate();
      return dt.isAfter(start) && !dt.isAfter(end);
    }).length;
  }

  /// Get detailed violation aggregation for today (no composite index).
  Future<ViolationAggregation> getTodayViolationDetails(String studentUID) async {
    final periodStart = DateHelpers.getCurrentPeriodStart();
    final all = await _fetchAllViolations(studentUID);
    final todayDocs = all.where((doc) {
      final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
      if (ts == null) return false;
      return (ts as Timestamp).toDate().isAfter(periodStart);
    }).toList();
    return ViolationAggregation.fromDocuments(todayDocs);
  }

  /// Get violation count for last N days (using 11 PM boundaries).
  /// Fetches all violations once, then counts per day in Dart.
  Future<Map<String, int>> getViolationsByDay(String studentUID, int days) async {
    final result = <String, int>{};
    final now = DateTime.now();
    final all = await _fetchAllViolations(studentUID);

    for (int i = 0; i < days; i++) {
      final periodEnd = DateHelpers.getCurrentPeriodEnd().subtract(Duration(days: i));
      final periodStart = periodEnd.subtract(const Duration(days: 1));

      if (periodStart.isAfter(now)) continue;

      final count = _countInPeriod(all, periodStart, periodEnd);
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

  /// Get violations for the current week (Monday to Sunday) – no composite index.
  Future<int> getWeeklyViolationsCount(String studentUID) async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day, 0, 0, 0);

    final all = await _fetchAllViolations(studentUID);
    return all.where((doc) {
      final ts = (doc.data() as Map<String, dynamic>)['timestamp'];
      if (ts == null) return false;
      return !(ts as Timestamp).toDate().isBefore(weekStart);
    }).length;
  }

  /// Get daily summaries for streak calculation – fetches once, filters in Dart.
  Future<List<DailyViolationSummary>> getDailySummaries(
    String studentUID,
    int daysBack,
  ) async {
    final summaries = <DailyViolationSummary>[];
    final now = DateTime.now();
    final all = await _fetchAllViolations(studentUID);

    for (int i = 0; i < daysBack; i++) {
      final periodEnd = DateHelpers.getCurrentPeriodEnd().subtract(Duration(days: i));
      final periodStart = periodEnd.subtract(const Duration(days: 1));

      if (periodStart.isAfter(now)) continue;

      final count = _countInPeriod(all, periodStart, periodEnd);
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

  /// Stream violations for real-time updates – no composite index, sorted client-side.
  Stream<List<Map<String, dynamic>>> streamRecentViolations(
    String studentUID, {
    int limit = 10,
  }) {
    return _violationsCollection
        .where('studentUID', isEqualTo: studentUID)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs.toList();
      docs.sort((a, b) {
        final ta = (a.data() as Map<String, dynamic>)['timestamp'];
        final tb = (b.data() as Map<String, dynamic>)['timestamp'];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return (tb as Timestamp).toDate().compareTo((ta as Timestamp).toDate());
      });
      return docs
          .take(limit)
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    });
  }
}
