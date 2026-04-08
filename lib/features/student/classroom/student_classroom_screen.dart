import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../services/smart_attendance_service.dart';

class StudentClassroomScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;

  const StudentClassroomScreen({super.key, required this.studentData});

  @override
  State<StudentClassroomScreen> createState() => _StudentClassroomScreenState();
}

class _StudentClassroomScreenState extends State<StudentClassroomScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  bool _loadingMonth = true;
  int _presentCount = 0;
  int _absentCount = 0;
  Map<String, _DayStatus> _dayStatuses = <String, _DayStatus>{};

  static const Map<int, String> _weekdayName = <int, String>{
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    _loadMonthSummary(_focusedDay);
  }

  String get _studentUid {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.trim().isNotEmpty) {
      return authUid.trim();
    }

    return (widget.studentData['uid'] ??
            widget.studentData['id'] ??
            widget.studentData['studentId'] ??
            widget.studentData['registrationNumber'] ??
            widget.studentData['regNo'] ??
            widget.studentData['rollNo'] ??
            '')
        .toString()
        .trim();
  }

  List<String> get _classCandidates {
    final raw = <dynamic>[
      widget.studentData['className'],
      widget.studentData['class'],
      widget.studentData['section'],
      widget.studentData['course'],
      widget.studentData['department'],
      widget.studentData['batch'],
      widget.studentData['classId'],
    ];

    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      if (seen.add(text)) out.add(text);
    }
    return out;
  }

  String _normalizePeriodKey(String raw) {
    final clean = raw.trim();
    final number = RegExp(r'(\d+)').firstMatch(clean)?.group(1);
    if (number != null) return 'period_$number';
    return clean.toLowerCase();
  }

  Future<Set<String>> _expectedClassPeriodsForWeekday(int weekday) async {
    final dayName = _weekdayName[weekday] ?? 'Monday';
    final lowerDay = dayName.toLowerCase();
    final classCandidates = _classCandidates;

    Future<Set<String>?> queryClass(String classId) async {
      var snap = await _db
          .collection('timetables')
          .doc(classId)
          .collection(dayName)
          .get();

      if (snap.docs.isEmpty) {
        snap = await _db
            .collection('timetables')
            .doc(classId)
            .collection(lowerDay)
            .get();
      }

      if (snap.docs.isEmpty) return null;

      final periods = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (!data.containsKey('monitoring') && data.containsKey('montoring')) {
          debugPrint('[StudentClassroom] Typo field found in ${doc.id}: montoring. Please migrate to monitoring.');
        }
        final monitoringRaw = data['monitoring'] ?? data['montoring'];
        final isClass = monitoringRaw == true || monitoringRaw == 'true';
        if (!isClass) continue;
        periods.add(_normalizePeriodKey(doc.id));
      }
      return periods;
    }

    for (final classId in classCandidates) {
      final periods = await queryClass(classId);
      if (periods != null) return periods;
    }

    final allClasses = await _db.collection('timetables').get();
    for (final classDoc in allClasses.docs) {
      if (classCandidates.contains(classDoc.id)) continue;
      final periods = await queryClass(classDoc.id);
      if (periods != null) return periods;
    }

    return <String>{};
  }

  Future<void> _loadMonthSummary(DateTime month) async {
    final uid = _studentUid;
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loadingMonth = false;
        _presentCount = 0;
        _absentCount = 0;
        _dayStatuses = <String, _DayStatus>{};
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loadingMonth = true);

    final monthPrefix = DateFormat('yyyy-MM').format(month);

    try {
      final records = await _db
          .collection('attendance_records')
          .where('studentUID', isEqualTo: uid)
          .get();

      var present = 0;
      var absent = 0;
      final byDate = <String, _MutableDayState>{};
      final expectedByWeekday = <int, Set<String>>{};

      for (final doc in records.docs) {
        final data = doc.data();
        final date = (data['date'] ?? '').toString();
        if (!date.startsWith(monthPrefix)) {
          continue;
        }

        final status = (data['status'] ?? '').toString().toLowerCase();
        final period = (data['period'] ?? '').toString();
        final isSubmitted = data['adminSubmitted'] == true;
        final day = byDate.putIfAbsent(date, _MutableDayState.new);

        if (status == 'present') {
          present++;
          day.hasPresent = true;
        } else if (status == 'absent') {
          absent++;
          day.hasAbsent = true;
        }

        if (isSubmitted && period.isNotEmpty) {
          day.submittedPeriodKeys.add(_normalizePeriodKey(period));
          if (status == 'present') {
            day.submittedPresentPeriodKeys.add(_normalizePeriodKey(period));
          }
        }
      }

      final dayStatuses = <String, _DayStatus>{};
      for (final entry in byDate.entries) {
        final date = entry.key;
        final value = entry.value;

        final parsedDate = DateTime.tryParse(date);
        final weekday = parsedDate?.weekday;
        final expectedPeriods = weekday == null
            ? <String>{}
            : await (() async {
                if (expectedByWeekday.containsKey(weekday)) {
                  return expectedByWeekday[weekday]!;
                }
                final loaded = await _expectedClassPeriodsForWeekday(weekday);
                expectedByWeekday[weekday] = loaded;
                return loaded;
              })();

        final hasAllExpectedSubmitted =
            expectedPeriods.isNotEmpty &&
            value.submittedPeriodKeys.length == expectedPeriods.length &&
            value.submittedPeriodKeys.containsAll(expectedPeriods);

        final isFullDayPresent =
            hasAllExpectedSubmitted &&
            value.submittedPresentPeriodKeys.length == expectedPeriods.length;

        if (value.hasAbsent) {
          dayStatuses[date] = _DayStatus.absent;
        } else if (isFullDayPresent) {
          dayStatuses[date] = _DayStatus.present;
        }
      }

      if (!mounted) return;
      setState(() {
        _presentCount = present;
        _absentCount = absent;
        _dayStatuses = dayStatuses;
        _loadingMonth = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _presentCount = 0;
        _absentCount = 0;
        _dayStatuses = <String, _DayStatus>{};
        _loadingMonth = false;
      });
    }
  }

  String _dayKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  Color _dateBorderColor(DateTime day, bool isToday, bool isSelected) {
    final status = _dayStatuses[_dayKey(day)];
    if (status == _DayStatus.present) return AppColors.success;
    if (status == _DayStatus.absent) return AppColors.danger;
    if (isSelected || isToday) return AppColors.lightBlue;
    return Colors.white.withValues(alpha: 0.16);
  }

  double get _percentage {
    final total = _presentCount + _absentCount;
    if (total == 0) return 0;
    return (_presentCount / total) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomSafePadding = mediaQuery.viewPadding.bottom + 24;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Classroom',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(),
                        const SizedBox(height: 16),
                        _buildCalendarCard(),
                        const SizedBox(height: 16),
                        _buildLegend(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    final attendanceRatio = _percentage / 100;
    return GlassCard(
      borderRadius: 22,
      child: _loadingMonth
          ? const SizedBox(
              height: 96,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.lightBlue),
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 118,
                  height: 118,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      CircularProgressIndicator(
                        value: attendanceRatio,
                        strokeWidth: 12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.success,
                        ),
                      ),
                      Center(
                        child: Text(
                          '${_percentage.toStringAsFixed(0)}%',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Monthly Attendance',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SummaryRow(
                        color: AppColors.success,
                        label: 'Present',
                        value: '$_presentCount Days',
                      ),
                      const SizedBox(height: 8),
                      _SummaryRow(
                        color: AppColors.danger,
                        label: 'Absent',
                        value: '$_absentCount Days',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCalendarCard() {
    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_focusedDay),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final previousMonth = DateTime(
                    _focusedDay.year,
                    _focusedDay.month - 1,
                    1,
                  );
                  setState(() {
                    _focusedDay = previousMonth;
                  });
                  _loadMonthSummary(previousMonth);
                },
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              IconButton(
                onPressed: () {
                  final nextMonth = DateTime(
                    _focusedDay.year,
                    _focusedDay.month + 1,
                    1,
                  );
                  setState(() {
                    _focusedDay = nextMonth;
                  });
                  _loadMonthSummary(nextMonth);
                },
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
              _loadMonthSummary(focusedDay);
            },
            onDaySelected: (selectedDay, focusedDay) async {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });

              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudentDayScheduleScreen(
                    studentData: widget.studentData,
                    selectedDate: selectedDay,
                  ),
                ),
              );

              await _loadMonthSummary(_focusedDay);
            },
            headerVisible: false,
            rowHeight: 48,
            calendarStyle: CalendarStyle(
              outsideDaysVisible: true,
              defaultTextStyle: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              weekendTextStyle: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              outsideTextStyle: GoogleFonts.poppins(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
              selectedTextStyle: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              selectedDecoration: BoxDecoration(
                color: AppColors.lightBlue.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.lightBlue, width: 1.5),
              ),
              todayDecoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.lightBlue.withValues(alpha: 0.9),
                  width: 1.4,
                ),
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.poppins(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              weekendStyle: GoogleFonts.poppins(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, false, false);
              },
              todayBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, true, false);
              },
              selectedBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, false, true);
              },
              outsideBuilder: (context, day, focusedDay) {
                return _buildDayCell(day, false, false, outside: true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    DateTime day,
    bool isToday,
    bool isSelected, {
    bool outside = false,
  }) {
    final hasStatus = _dayStatuses.containsKey(_dayKey(day));
    final borderColor = _dateBorderColor(day, isToday, isSelected);

    final textColor = outside ? AppColors.textSecondary : Colors.white;

    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (isSelected && !hasStatus)
              ? AppColors.lightBlue.withValues(alpha: 0.28)
              : Colors.transparent,
          border: Border.all(color: borderColor, width: 1.3),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: AppColors.success, label: 'Present'),
          const SizedBox(width: 22),
          _LegendDot(color: AppColors.danger, label: 'Absent'),
        ],
      ),
    );
  }
}

class StudentDayScheduleScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;
  final DateTime selectedDate;

  const StudentDayScheduleScreen({
    super.key,
    required this.studentData,
    required this.selectedDate,
  });

  @override
  State<StudentDayScheduleScreen> createState() =>
      _StudentDayScheduleScreenState();
}

class _StudentDayScheduleScreenState extends State<StudentDayScheduleScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final SmartAttendanceService _attendance = SmartAttendanceService.instance;

  final List<_TimetablePeriod> _periods = <_TimetablePeriod>[];
  final Map<String, String> _statusByPeriod = <String, String>{};
  final Map<String, bool> _submittedByPeriod = <String, bool>{};

  bool _loading = true;
  String? _error;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  static const Map<int, String> _dayNames = <int, String>{
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    _loadDayData();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _studentUid {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.trim().isNotEmpty) {
      return authUid.trim();
    }

    return (widget.studentData['uid'] ??
            widget.studentData['id'] ??
            widget.studentData['studentId'] ??
            widget.studentData['registrationNumber'] ??
            widget.studentData['regNo'] ??
            widget.studentData['rollNo'] ??
            '')
        .toString()
        .trim();
  }

  String get _studentName {
    return (widget.studentData['name'] ??
            widget.studentData['studentName'] ??
            'Student')
        .toString();
  }

  bool get _isToday {
    return isSameDay(widget.selectedDate, DateTime.now());
  }

  int get _currentMinutes => _now.hour * 60 + _now.minute;

  bool _shouldAutoMarkAbsent(_TimetablePeriod period) {
    if (!period.isClass) return false;

    final selectedDayOnlyDate = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    final nowOnlyDate = DateTime(_now.year, _now.month, _now.day);

    if (selectedDayOnlyDate.isBefore(nowOnlyDate)) {
      return true;
    }

    if (!isSameDay(selectedDayOnlyDate, nowOnlyDate)) {
      return false;
    }

    return _currentMinutes >= period.endTime;
  }

  _TimetablePeriod? get _activePeriod {
    if (!_isToday) return null;
    final minutes = _currentMinutes;
    for (final period in _periods) {
      if (!period.isClass) continue;
      if (minutes >= period.startTime && minutes < period.endTime) {
        return period;
      }
    }
    return null;
  }

  Future<void> _loadDayData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _periods.clear();
      _statusByPeriod.clear();
      _submittedByPeriod.clear();
    });

    try {
      final periods = await _loadTimetableForDate(widget.selectedDate);
      final statusMap = await _loadAttendanceForDate(widget.selectedDate);

      if (!mounted) return;
      setState(() {
        _periods.addAll(periods);
        for (final entry in statusMap.entries) {
          _statusByPeriod[entry.key] = entry.value.status;
          _submittedByPeriod[entry.key] = entry.value.adminSubmitted;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load schedule: $e';
        _loading = false;
      });
    }
  }

  Future<List<_TimetablePeriod>> _loadTimetableForDate(DateTime date) async {
    final dayName = _dayNames[date.weekday] ?? 'Monday';
    final lowerDay = dayName.toLowerCase();

    for (final classId in _classCandidates) {
      final fromCandidate = await _queryDay(classId, dayName, lowerDay);
      if (fromCandidate != null) {
        return fromCandidate;
      }
    }

    final allClasses = await _db.collection('timetables').get();
    for (final classDoc in allClasses.docs) {
      if (_classCandidates.contains(classDoc.id)) continue;
      final discovered = await _queryDay(classDoc.id, dayName, lowerDay);
      if (discovered != null) {
        return discovered;
      }
    }

    return const <_TimetablePeriod>[];
  }

  Future<List<_TimetablePeriod>?> _queryDay(
    String classId,
    String dayName,
    String lowerDay,
  ) async {
    var snap = await _db
        .collection('timetables')
        .doc(classId)
        .collection(dayName)
        .get();

    if (snap.docs.isEmpty) {
      snap = await _db
          .collection('timetables')
          .doc(classId)
          .collection(lowerDay)
          .get();
    }

    if (snap.docs.isEmpty) {
      return null;
    }

    final entries = snap.docs.map((doc) {
      final data = doc.data();
      if (!data.containsKey('monitoring') && data.containsKey('montoring')) {
        debugPrint('[StudentClassroom] Typo field found in ${doc.id}: montoring. Please migrate to monitoring.');
      }
      final monitoringRaw = data['monitoring'] ?? data['montoring'];
      final isClass = monitoringRaw == true || monitoringRaw == 'true';
      final start = (data['startTime'] as num?)?.toInt() ?? 0;
      final end = (data['endTime'] as num?)?.toInt() ?? 0;
      final subject = (data['subject'] ?? doc.id).toString();

      return _TimetablePeriod(
        id: doc.id,
        subject: subject,
        startTime: start,
        endTime: end,
        isClass: isClass,
      );
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

    return entries;
  }

  Future<Map<String, _PeriodAttendanceState>> _loadAttendanceForDate(
    DateTime date,
  ) async {
    final uid = _studentUid;
    if (uid.isEmpty) {
      return const <String, _PeriodAttendanceState>{};
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    final snap = await _db
        .collection('attendance_records')
        .where('studentUID', isEqualTo: uid)
        .where('date', isEqualTo: dateKey)
        .get();

    final out = <String, _PeriodAttendanceState>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final period = (data['period'] ?? '').toString();
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (period.isEmpty || status.isEmpty) continue;
      out[_normalizePeriodKey(period)] = _PeriodAttendanceState(
        status: status,
        adminSubmitted: data['adminSubmitted'] == true,
      );
    }

    return out;
  }

  List<String> get _classCandidates {
    final raw = <dynamic>[
      widget.studentData['className'],
      widget.studentData['class'],
      widget.studentData['section'],
      widget.studentData['course'],
      widget.studentData['department'],
      widget.studentData['batch'],
      widget.studentData['classId'],
    ];

    final out = <String>[];
    final seen = <String>{};

    for (final value in raw) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      if (seen.add(text)) {
        out.add(text);
      }
    }

    return out;
  }

  String _normalizePeriodKey(String raw) {
    final clean = raw.trim();
    final number = RegExp(r'(\d+)').firstMatch(clean)?.group(1);
    if (number != null) {
      return 'period_$number';
    }
    return clean.toLowerCase();
  }

  String _statusForPeriod(String periodId) {
    final key = _normalizePeriodKey(periodId);
    return _statusByPeriod[key] ?? '';
  }

  bool _isSubmittedForPeriod(String periodId) {
    final key = _normalizePeriodKey(periodId);
    return _submittedByPeriod[key] == true;
  }

  String _displayDate(DateTime date) {
    final dayShort = DateFormat('EEE').format(date);
    final value = DateFormat('d MMM yyyy').format(date);
    return '$dayShort, $value';
  }

  String _formatMinutes(int minutes) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final suffix = hour24 < 12 ? 'AM' : 'PM';
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);

    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _onPeriodTap(_TimetablePeriod period) async {
    final status = _statusForPeriod(period.id);

    if (!period.isClass) {
      _showInfo('This is break period. Attendance code not required.');
      return;
    }

    if (status == 'present') {
      _showInfo('Attendance already marked present for this period.');
      return;
    }

    if (!_isToday) {
      _showInfo('Only today active period supports attendance code entry.');
      return;
    }

    final active = _activePeriod;
    if (active == null ||
        _normalizePeriodKey(active.id) != _normalizePeriodKey(period.id)) {
      _showInfo('You can submit only for current active period.');
      return;
    }

    await _openCodeEntry(period);
  }

  void _showInfo(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openCodeEntry(_TimetablePeriod period) async {
    final controller = TextEditingController();
    var loading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !loading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogInnerContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0B1336),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                'Enter Attendance Code',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Period: ${period.id}',
                    style: GoogleFonts.poppins(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '6 digit code',
                      hintStyle: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final code = controller.text.trim();
                          if (code.isEmpty) {
                            _showInfo('Attendance code enter pannunga');
                            return;
                          }

                          if (dialogInnerContext.mounted) {
                            setDialogState(() => loading = true);
                          }

                          final result = await _attendance.submitAttendance(
                            code: code,
                            period: period.id,
                            studentName: _studentName,
                          );

                          if (dialogInnerContext.mounted) {
                            setDialogState(() => loading = false);
                          }
                          if (!mounted) return;

                          if (result.success) {
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            _showInfo('Attendance marked successfully');
                            await _loadDayData();
                          } else {
                            _showInfo(result.message);
                          }
                        },
                  child: Text(loading ? 'Submitting...' : 'Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _displayDate(widget.selectedDate),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.lightBlue,
                          ),
                        )
                      : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _periods.isEmpty
                      ? Center(
                          child: Text(
                            'No periods configured for this date',
                            style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _periods.length,
                          itemBuilder: (context, index) {
                            final period = _periods[index];
                            final status = _statusForPeriod(period.id);
                            final isSubmitted = _isSubmittedForPeriod(
                              period.id,
                            );
                            final autoAbsent =
                                status.isEmpty && _shouldAutoMarkAbsent(period);

                            Color borderColor = Colors.white.withValues(
                              alpha: 0.18,
                            );
                            String statusLabel = '';
                            Color statusColor = AppColors.textSecondary;

                            if (status == 'present') {
                              borderColor = AppColors.success;
                              statusColor = isSubmitted
                                ? AppColors.success
                                : AppColors.lightBlue;
                              statusLabel = isSubmitted
                                ? 'Present'
                                : 'Present (Pending)';
                            } else if (status == 'absent' || autoAbsent) {
                              borderColor = AppColors.danger;
                              if (autoAbsent) {
                                statusColor = AppColors.danger;
                                statusLabel = 'Absent';
                              } else {
                                statusColor = isSubmitted
                                  ? AppColors.danger
                                  : AppColors.lightBlue;
                                statusLabel = isSubmitted
                                  ? 'Absent'
                                  : 'Absent (Pending)';
                              }
                            }

                            final showStatus = period.isClass && statusLabel.isNotEmpty;

                            final isActive =
                                _isToday &&
                                _currentMinutes >= period.startTime &&
                                _currentMinutes < period.endTime &&
                                period.isClass;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _onPeriodTap(period),
                                child: GlassCard(
                                  borderRadius: 16,
                                  borderColor: isActive
                                      ? AppColors.lightBlue
                                      : borderColor,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: statusColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        child: Icon(
                                          period.isClass
                                              ? Icons.menu_book_rounded
                                              : Icons.free_breakfast_rounded,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              period.subject,
                                              style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_formatMinutes(period.startTime)} - ${_formatMinutes(period.endTime)}',
                                              style: GoogleFonts.poppins(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          if (showStatus)
                                            Text(
                                              statusLabel,
                                              style: GoogleFonts.poppins(
                                                color: statusColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          if (isActive)
                                            Text(
                                              'Active now',
                                              style: GoogleFonts.poppins(
                                                color: AppColors.lightBlue,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _SummaryRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$label:',
            style: GoogleFonts.poppins(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: AppColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TimetablePeriod {
  final String id;
  final String subject;
  final int startTime;
  final int endTime;
  final bool isClass;

  const _TimetablePeriod({
    required this.id,
    required this.subject,
    required this.startTime,
    required this.endTime,
    required this.isClass,
  });
}

class _PeriodAttendanceState {
  final String status;
  final bool adminSubmitted;

  const _PeriodAttendanceState({
    required this.status,
    required this.adminSubmitted,
  });
}

enum _DayStatus { present, absent }

class _MutableDayState {
  bool hasPresent = false;
  bool hasAbsent = false;
  final Set<String> submittedPeriodKeys = <String>{};
  final Set<String> submittedPresentPeriodKeys = <String>{};
}
