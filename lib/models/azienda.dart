// lib/models/azienda.dart

import 'dart:convert';
import 'package:flutter/material.dart';

@immutable
class ScheduleConfig {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final List<int> activeDays;
  final int lunchBreakMinutes;
  final String? automationStartDate;

  const ScheduleConfig({
    this.enabled = false,
    this.start = const TimeOfDay(hour: 9, minute: 0),
    this.end = const TimeOfDay(hour: 18, minute: 0),
    this.activeDays = const [1, 2, 3, 4, 5],
    this.lunchBreakMinutes = 60,
    this.automationStartDate,
  });

  ScheduleConfig copyWith({
    bool? enabled,
    TimeOfDay? start,
    TimeOfDay? end,
    List<int>? activeDays,
    int? lunchBreakMinutes,
    String? automationStartDate,
  }) => ScheduleConfig(
    enabled: enabled ?? this.enabled,
    start: start ?? this.start,
    end: end ?? this.end,
    activeDays: activeDays ?? this.activeDays,
    lunchBreakMinutes: lunchBreakMinutes ?? this.lunchBreakMinutes,
    automationStartDate: automationStartDate ?? this.automationStartDate,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'start': '${start.hour}:${start.minute}',
    'end': '${end.hour}:${end.minute}',
    'activeDays': activeDays,
    'lunchBreakMinutes': lunchBreakMinutes,
    'automationStartDate': automationStartDate,
  };

  factory ScheduleConfig.fromJson(Map<String, dynamic> j) {
    TimeOfDay parseTime(String? raw, TimeOfDay fallback) {
      if (raw == null) return fallback;
      final parts = raw.split(':');
      if (parts.length != 2) return fallback;
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? fallback.hour,
        minute: int.tryParse(parts[1]) ?? fallback.minute,
      );
    }
    return ScheduleConfig(
      enabled: j['enabled'] as bool? ?? false,
      start: parseTime(j['start'] as String?, const TimeOfDay(hour: 9, minute: 0)),
      end: parseTime(j['end'] as String?, const TimeOfDay(hour: 18, minute: 0)),
      activeDays: List<int>.from(j['activeDays'] as List? ?? [1, 2, 3, 4, 5]),
      lunchBreakMinutes: j['lunchBreakMinutes'] as int? ?? 60,
      automationStartDate: j['automationStartDate'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleConfig &&
          enabled == other.enabled &&
          start == other.start &&
          end == other.end &&
          lunchBreakMinutes == other.lunchBreakMinutes &&
          automationStartDate == other.automationStartDate;

  @override
  int get hashCode => Object.hash(enabled, start, end, lunchBreakMinutes, automationStartDate);
}

@immutable
class Azienda {
  final int? id;
  final String name;
  final double hourlyRate;
  final double overtimeRate;
  final ScheduleConfig scheduleConfig;

  const Azienda({
    this.id,
    required this.name,
    this.hourlyRate = 0.0,
    this.overtimeRate = 0.0,
    this.scheduleConfig = const ScheduleConfig(),
  });

  /// Net working hours per day from the schedule — overtime threshold.
  double get standardHoursPerDay {
    final startMin = scheduleConfig.start.hour * 60 + scheduleConfig.start.minute;
    final endMin   = scheduleConfig.end.hour   * 60 + scheduleConfig.end.minute;
    final net      = endMin - startMin - scheduleConfig.lunchBreakMinutes;
    return net > 0 ? net / 60.0 : 8.0;
  }

  Azienda copyWith({
    int? id,
    String? name,
    double? hourlyRate,
    double? overtimeRate,
    ScheduleConfig? scheduleConfig,
  }) => Azienda(
    id: id ?? this.id,
    name: name ?? this.name,
    hourlyRate: hourlyRate ?? this.hourlyRate,
    overtimeRate: overtimeRate ?? this.overtimeRate,
    scheduleConfig: scheduleConfig ?? this.scheduleConfig,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'hourly_rate': hourlyRate,
    'overtime_rate': overtimeRate,
    'schedule_config': jsonEncode(scheduleConfig.toJson()),
  };

  factory Azienda.fromMap(Map<String, dynamic> m) => Azienda(
    id: m['id'] as int?,
    name: m['name'] as String,
    hourlyRate: (m['hourly_rate'] as num?)?.toDouble() ?? 0.0,
    overtimeRate: (m['overtime_rate'] as num?)?.toDouble() ?? 0.0,
    scheduleConfig: m['schedule_config'] != null
        ? ScheduleConfig.fromJson(jsonDecode(m['schedule_config'] as String) as Map<String, dynamic>)
        : const ScheduleConfig(),
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is Azienda && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Azienda(id: $id, name: $name)';
}
