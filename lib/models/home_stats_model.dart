/// Model class representing student home dashboard statistics
class HomeStats {
  final int todayViolations;
  final int behaviorStreak;
  final int tasksCompleted;
  final int tasksTotal;

  HomeStats({
    this.todayViolations = 0,
    this.behaviorStreak = 0,
    this.tasksCompleted = 0,
    this.tasksTotal = 0,
  });

  /// Creates a copy with updated fields
  HomeStats copyWith({
    int? todayViolations,
    int? behaviorStreak,
    int? tasksCompleted,
    int? tasksTotal,
  }) {
    return HomeStats(
      todayViolations: todayViolations ?? this.todayViolations,
      behaviorStreak: behaviorStreak ?? this.behaviorStreak,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
      tasksTotal: tasksTotal ?? this.tasksTotal,
    );
  }

  /// Returns percentage of tasks completed (0-100)
  double get taskCompletionPercentage {
    if (tasksTotal == 0) return 0.0;
    return (tasksCompleted / tasksTotal) * 100;
  }

  /// Checks if student has any violations today
  bool get hasViolationsToday => todayViolations > 0;

  /// Checks if student has active streak
  bool get hasActiveStreak => behaviorStreak > 0;

  @override
  String toString() {
    return 'HomeStats(violations: $todayViolations, streak: $behaviorStreak days, '
           'tasks: $tasksCompleted/$tasksTotal)';
  }
}
