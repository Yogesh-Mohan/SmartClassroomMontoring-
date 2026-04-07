import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';

class TimetableScreen extends StatefulWidget {
  final Map<String, dynamic> studentData;
  const TimetableScreen({super.key, required this.studentData});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<_PeriodEntry> _periods = [];
  bool _loading = false;
  String? _error;
  String? _resolvedClass;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  static const _dayNames = {
    1: 'Monday', 2: 'Tuesday', 3: 'Wednesday',
    4: 'Thursday', 5: 'Friday', 6: 'Saturday', 7: 'Sunday',
  };

  // Current time in minutes from midnight
  int get _currentMinutes => _now.hour * 60 + _now.minute;

  // Is the selected day today?
  bool get _isToday => isSameDay(_selectedDay ?? _focusedDay, DateTime.now());

  // Find the currently active period (only when viewing today)
  _PeriodEntry? get _activePeriod {
    if (!_isToday) return null;
    final cm = _currentMinutes;
    for (final p in _periods) {
      if (cm >= p.startTime && cm < p.endTime) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPeriods(_selectedDay ?? _focusedDay);
    // Refresh clock every 30 seconds so active period updates live
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final hour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${hour.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  // Include every possible field name the student doc might use
  List<String> get _classCandidates {
    final d = widget.studentData;
    final raw = [
      d['className'], d['class'], d['section'],
      d['course'], d['department'], d['batch'], d['classId'],
    ];
    return raw
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .map((v) => v.toString().trim())
        .toList();
  }

  Future<void> _loadPeriods(DateTime day) async {
    setState(() { _loading = true; _error = null; _periods = []; });

    final dayName  = _dayNames[day.weekday] ?? 'Monday'; // e.g. "Wednesday"
    final lowerDay = dayName.toLowerCase();              // e.g. "wednesday"

    final db = FirebaseFirestore.instance;
    final candidates = _classCandidates;

    try {
      List<_PeriodEntry>? found;
      String? foundClass;

      // Try each candidate class
      for (final cls in candidates) {
        final result = await _queryDay(db, cls, dayName, lowerDay);
        if (result != null) { found = result; foundClass = cls; break; }
      }

      // Auto-discover if no candidate matched
      if (found == null) {
        final all = await db.collection('timetables').get();
        for (final doc in all.docs) {
          if (candidates.contains(doc.id)) continue;
          final result = await _queryDay(db, doc.id, dayName, lowerDay);
          if (result != null) { found = result; foundClass = doc.id; break; }
        }
      }

      if (!mounted) return;
      setState(() {
        _periods = found ?? [];
        _resolvedClass = foundClass;
        _loading = false;
        _error = found == null ? 'No timetable found for your class.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Error loading timetable: $e'; });
    }
  }

  Future<List<_PeriodEntry>?> _queryDay(
      FirebaseFirestore db, String cls, String dayName, String lowerDay) async {
    QuerySnapshot<Map<String, dynamic>> snap;

    snap = await db.collection('timetables').doc(cls).collection(dayName).get();
    if (snap.docs.isEmpty) {
      snap = await db.collection('timetables').doc(cls).collection(lowerDay).get();
    }
    if (snap.docs.isEmpty) return null;

    final entries = snap.docs.map((doc) {
      final data = doc.data();
      if (!data.containsKey('monitoring') && data.containsKey('montoring')) {
        debugPrint('[TimetableScreen] Typo field found in ${doc.id}: montoring. Please migrate to monitoring.');
      }
      final raw  = data['monitoring'];
      final isClass = (raw == true || raw == 'true');
      final start = (data['startTime'] as num?)?.toInt() ?? 0;
      final end   = (data['endTime']   as num?)?.toInt() ?? 0;
      final subject = (data['subject'] ?? doc.id).toString();
      return _PeriodEntry(
        id: doc.id,
        subject: subject,
        startTime: start,
        endTime: end,
        isClass: isClass,
      );
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.primaryVertical),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Schedule',
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white))
                      .animate()
                      .fadeIn(),
                  Text(_resolvedClass != null
                      ? 'Class: $_resolvedClass'
                      : 'Your weekly class timetable',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textSecondary))
                      .animate()
                      .fadeIn(delay: 80.ms),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: TableCalendar(
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2026, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    _loadPeriods(selectedDay);
                  },
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: AppColors.lightBlue.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: const BoxDecoration(
                      color: AppColors.lightBlue,
                      shape: BoxShape.circle,
                    ),
                    defaultTextStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                    weekendTextStyle: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                    outsideTextStyle: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                    todayTextStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                    selectedTextStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    leftChevronIcon: const Icon(Icons.chevron_left, color: AppColors.lightBlue),
                    rightChevronIcon: const Icon(Icons.chevron_right, color: AppColors.lightBlue),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                    weekendStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ).animate().fadeIn(delay: 150.ms),
            ),
            // ── Current Status Banner (today only) ──────────────────────
            if (_isToday && !_loading && _periods.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Builder(builder: (context) {
                  final active = _activePeriod;
                  final isClass = active?.isClass ?? false;
                  final color  = active == null
                      ? Colors.grey
                      : isClass ? AppColors.lightBlue : Colors.orange;
                  final icon   = active == null
                      ? Icons.schedule_outlined
                      : isClass ? Icons.cast_for_education_outlined : Icons.free_breakfast_outlined;
                  final status = active == null
                      ? 'No active period right now'
                      : isClass ? '🔵 CLASS TIME — Monitoring ON' : '🟠 BREAK TIME — Monitoring OFF';
                  final sub    = active == null
                      ? 'Next: ${_nextPeriodText()}'
                      : '${active.subject}  •  ${_fmt(active.startTime)} – ${_fmt(active.endTime)}';
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.5), width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                              Text(sub,
                                  style: GoogleFonts.poppins(
                                      fontSize: 11, color: Colors.white70)),
                            ],
                          ),
                        ),
                        Text(
                          '${_now.hour.toString().padLeft(2,'0')}:${_now.minute.toString().padLeft(2,'0')}',
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                      ],
                    ),
                  );
                }),
              ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('Periods for this day',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.lightBlue))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                          ))
                      : _periods.isEmpty
                          ? Center(
                              child: GlassCard(
                                child: Text('No periods found for this day',
                                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                              ))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                              itemCount: _periods.length,
                              itemBuilder: (ctx, i) {
                                final p = _periods[i];
                                final isClass = p.isClass;
                                final color = isClass ? AppColors.lightBlue : Colors.orange;
                                final icon  = isClass ? Icons.class_outlined : Icons.free_breakfast_outlined;
                                final label = isClass ? 'Class Time' : 'Break Time';
                                // Highlight the currently active period
                                final isActive = _isToday &&
                                    _currentMinutes >= p.startTime &&
                                    _currentMinutes < p.endTime;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GlassCard(
                                    borderRadius: 14,
                                    borderColor: isActive ? color : null,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: color.withValues(alpha: isActive ? 0.4 : 0.2),
                                          child: Icon(icon, color: color, size: 18),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(p.subject,
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white)),
                                              Text('${_fmt(p.startTime)} – ${_fmt(p.endTime)}',
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 11, color: AppColors.textSecondary)),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: color.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(label,
                                              style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: color)),
                                        ),
                                      ],
                                    ),
                                  ).animate().fadeIn(delay: Duration(milliseconds: i * 60)).slideX(begin: 0.04),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodEntry {
  final String id;
  final String subject;
  final int startTime;
  final int endTime;
  final bool isClass;
  const _PeriodEntry({
    required this.id,
    required this.subject,
    required this.startTime,
    required this.endTime,
    required this.isClass,
  });
}

extension on _TimetableScreenState {
  String _nextPeriodText() {
    final cm = _currentMinutes;
    final upcoming = _periods
        .where((p) => p.startTime > cm)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (upcoming.isEmpty) return 'No more periods today';
    final n = upcoming.first;
    return '${n.subject} at ${_fmt(n.startTime)}';
  }
}
