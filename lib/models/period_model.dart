import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Model class representing a single class period in the timetable
class Period {
  final String id;
  final String subject;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String room;
  final bool isBreak;
  final bool isMonitoring;

  Period({
    required this.id,
    required this.subject,
    required this.startTime,
    required this.endTime,
    required this.room,
    this.isBreak = false,
    this.isMonitoring = true,
  });

  /// Creates a Period from a Firestore document snapshot
  factory Period.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    TimeOfDay minutesToTimeOfDay(int minutes) {
      final int hour = minutes ~/ 60;
      final int minute = minutes % 60;
      return TimeOfDay(hour: hour, minute: minute);
    }

    int parseMinutes(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final asInt = int.tryParse(value.trim());
        if (asInt != null) return asInt;
        final parts = value.split(':');
        if (parts.length == 2) {
          final h = int.tryParse(parts[0].trim()) ?? 0;
          final m = int.tryParse(parts[1].trim()) ?? 0;
          return (h * 60) + m;
        }
      }
      return 0;
    }

    bool parseBool(dynamic value, {bool fallback = true}) {
      if (value is bool) return value;
      if (value is String) {
        final v = value.trim().toLowerCase();
        if (v == 'true' || v == '1' || v == 'yes') return true;
        if (v == 'false' || v == '0' || v == 'no') return false;
      }
      if (value is num) return value != 0;
      return fallback;
    }

    final startMinutes = parseMinutes(data['startTime']);
    final endMinutes = parseMinutes(data['endTime']);
    final monitoringRaw = data.containsKey('monitoring')
        ? data['monitoring']
        : data['montoring'];
    final breakRaw = data.containsKey('isBreak') ? data['isBreak'] : data['break'];
    final subject = (data['subject'] ?? data['name'] ?? doc.id).toString();
    final room = (data['room'] ?? data['classRoom'] ?? data['location'] ?? 'N/A').toString();

    return Period(
      id: doc.id,
      subject: subject,
      startTime: minutesToTimeOfDay(startMinutes),
      endTime: minutesToTimeOfDay(endMinutes),
      room: room,
      isBreak: parseBool(breakRaw, fallback: false),
      isMonitoring: parseBool(monitoringRaw, fallback: true),
    );
  }

  /// Formats the start and end time into a string like "09:00 – 10:30"
  String get formattedTime {
    final start = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    final end = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return '$start – $end';
  }

  @override
  String toString() {
    return 'Period(subject: $subject, time: $formattedTime, room: $room)';
  }
}
