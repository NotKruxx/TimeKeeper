// lib/models/azienda.dart

import 'dart:convert';
import 'package:flutter/material.dart';

class ScheduleConfig {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final List<int> activeDays; // 1-7 for Mon-Sun
  final int lunchBreakMinutes;
  final String? automationStartDate; // YYYY-MM-DD

  ScheduleConfig({
    this.enabled = false,
    this.start = const TimeOfDay(hour: 9, minute: 0),
    this.end = const TimeOfDay(hour: 18, minute: 0),
    this.activeDays = const [1, 2, 3, 4, 5],
    this.lunchBreakMinutes = 60,
    this.automationStartDate,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'start': '${start.hour}:${start.minute}',
        'end': '${end.hour}:${end.minute}',
        'activeDays': activeDays,
        'lunchBreakMinutes': lunchBreakMinutes,
        'automationStartDate': automationStartDate,
      };

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    final startParts = (json['start'] as String? ?? '9:0').split(':');
    final endParts = (json['end'] as String? ?? '18:0').split(':');
    return ScheduleConfig(
      enabled: json['enabled'] ?? false,
      start: TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1])),
      end: TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1])),
      activeDays: List<int>.from(json['activeDays'] ?? [1, 2, 3, 4, 5]),
      lunchBreakMinutes: json['lunchBreakMinutes'] ?? 60,
      automationStartDate: json['automationStartDate'],
    );
  }
}

class Azienda {
  final int? id;
  final String name;
  final double hourlyRate;
  final double overtimeRate;
  final ScheduleConfig scheduleConfig;

  Azienda({
    this.id,
    required this.name,
    this.hourlyRate = 0.0,
    this.overtimeRate = 0.0,
    ScheduleConfig? scheduleConfig,
  }) : scheduleConfig = scheduleConfig ?? ScheduleConfig();

  double get overtimeThreshold {
    final startMinutes = scheduleConfig.start.hour * 60 + scheduleConfig.start.minute;
    final endMinutes = scheduleConfig.end.hour * 60 + scheduleConfig.end.minute;
    final breakMinutes = scheduleConfig.lunchBreakMinutes;
    return (endMinutes - startMinutes - breakMinutes) / 60.0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hourly_rate': hourlyRate,
      'overtime_rate': overtimeRate,
      'schedule_config': jsonEncode(scheduleConfig.toJson()),
    };
  }

  factory Azienda.fromMap(Map<String, dynamic> map) {
    return Azienda(
      id: map['id'],
      name: map['name'],
      hourlyRate: (map['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      overtimeRate: (map['overtime_rate'] as num?)?.toDouble() ?? 0.0,
      scheduleConfig: map['schedule_config'] != null ? ScheduleConfig.fromJson(jsonDecode(map['schedule_config'])) : ScheduleConfig(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Azienda && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}