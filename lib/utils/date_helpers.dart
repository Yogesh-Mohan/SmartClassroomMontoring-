/// Date helper utilities for handling 11 PM day boundaries
/// and violation tracking periods
class DateHelpers {
  /// Returns today's date at 11:00 PM (23:00:00)
  /// This marks the end of the current violation tracking period
  static DateTime getToday11PM() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 0, 0);
  }

  /// Returns yesterday's date at 11:00 PM (23:00:00)
  /// This marks the start of the current violation tracking period
  static DateTime getYesterday11PM() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    return DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 0, 0);
  }

  /// Returns the start of the current tracking period (previous 11 PM)
  /// If current time is before 11 PM today, returns yesterday 11 PM
  /// If current time is after 11 PM today, returns today 11 PM
  static DateTime getCurrentPeriodStart() {
    final now = DateTime.now();
    final today11PM = getToday11PM();
    
    if (now.isBefore(today11PM)) {
      return getYesterday11PM();
    } else {
      return today11PM;
    }
  }

  /// Returns the end of the current tracking period (next 11 PM)
  /// If current time is before 11 PM today, returns today 11 PM
  /// If current time is after 11 PM today, returns tomorrow 11 PM
  static DateTime getCurrentPeriodEnd() {
    final now = DateTime.now();
    final today11PM = getToday11PM();
    
    if (now.isBefore(today11PM)) {
      return today11PM;
    } else {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 0, 0);
    }
  }

  /// Returns a list of 11 PM to 11 PM date ranges for streak calculation
  /// Goes back [daysBack] number of days from current period
  /// Each range represents one "day" in the violation tracking system
  static List<DateTimeRange> getDayBlocksForStreak(int daysBack) {
    final blocks = <DateTimeRange>[];
    final currentPeriodEnd = getCurrentPeriodEnd();
    
    for (int i = 0; i < daysBack; i++) {
      final endDate = currentPeriodEnd.subtract(Duration(days: i));
      final startDate = endDate.subtract(const Duration(days: 1));
      
      blocks.add(DateTimeRange(
        start: DateTime(startDate.year, startDate.month, startDate.day, 23, 0, 0),
        end: DateTime(endDate.year, endDate.month, endDate.day, 23, 0, 0),
      ));
    }
    
    return blocks;
  }

  /// Checks if a given timestamp falls within the current tracking period
  static bool isInCurrentPeriod(DateTime timestamp) {
    final start = getCurrentPeriodStart();
    final end = getCurrentPeriodEnd();
    
    return timestamp.isAfter(start) && timestamp.isBefore(end);
  }

  /// Formats a DateTime to a human-readable string for debugging
  static String formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Represents a date range with start and end times
class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});

  bool contains(DateTime dateTime) {
    return dateTime.isAfter(start) && dateTime.isBefore(end);
  }

  @override
  String toString() {
    return 'DateTimeRange(${DateHelpers.formatDateTime(start)} - ${DateHelpers.formatDateTime(end)})';
  }
}
