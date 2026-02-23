import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/widgets/glass_card.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  static const Map<String, List<_ClassEntry>> _schedule = {
    'Monday': [
      _ClassEntry('Mathematics', '09:00â€“10:30', 'Room 101', Icons.calculate_outlined),
      _ClassEntry('Physics', '11:00â€“12:30', 'Lab 1', Icons.science_outlined),
      _ClassEntry('English', '14:00â€“15:30', 'Room 202', Icons.menu_book_outlined),
    ],
    'Tuesday': [
      _ClassEntry('Computer Science', '09:00â€“10:30', 'Room 303', Icons.computer_outlined),
      _ClassEntry('Chemistry', '11:00â€“12:30', 'Lab 2', Icons.biotech_outlined),
    ],
    'Wednesday': [
      _ClassEntry('Mathematics', '09:00â€“10:30', 'Room 101', Icons.calculate_outlined),
      _ClassEntry('Physical Education', '14:00â€“15:30', 'Ground', Icons.sports_outlined),
    ],
    'Thursday': [
      _ClassEntry('Computer Science', '09:00â€“10:30', 'Room 303', Icons.computer_outlined),
      _ClassEntry('Physics', '11:00â€“12:30', 'Lab 1', Icons.science_outlined),
      _ClassEntry('English', '14:00â€“15:30', 'Room 202', Icons.menu_book_outlined),
    ],
    'Friday': [
      _ClassEntry('Chemistry', '09:00â€“10:30', 'Lab 2', Icons.biotech_outlined),
      _ClassEntry('Mathematics', '11:00â€“12:30', 'Room 101', Icons.calculate_outlined),
    ],
  };

  List<_ClassEntry> get _todayClasses {
    final day = _selectedDay ?? _focusedDay;
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final name = names[(day.weekday - 1).clamp(0, 6)];
    return _schedule[name] ?? [];
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
                  Text('Your weekly class timetable',
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
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('Classes for this day',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                itemCount: _todayClasses.isEmpty ? 1 : _todayClasses.length,
                itemBuilder: (ctx, i) {
                  if (_todayClasses.isEmpty) {
                    return GlassCard(
                      child: Text('No classes scheduled',
                          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                    );
                  }
                  final c = _todayClasses[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      borderRadius: 14,
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.lightBlue.withValues(alpha: 0.2),
                            child: Icon(c.icon, color: AppColors.lightBlue, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.subject,
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                Text('${c.time} â€¢ ${c.room}',
                                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
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

class _ClassEntry {
  final String subject;
  final String time;
  final String room;
  final IconData icon;
  const _ClassEntry(this.subject, this.time, this.room, this.icon);
}
