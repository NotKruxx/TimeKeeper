// lib/models/azienda.dart

import 'dart:convert';
import 'package:flutter/material.dart';

class ScheduleConfig {
  bool enabled;
  TimeOfDay start;
  TimeOfDay end;
  List<int> activeDays; 
  int lunchBreakMinutes;
  String? automationStartDate; 

  ScheduleConfig({
    this.enabled = false,
    this.start = const TimeOfDay(hour: 9, minute: 0),
    this.end = const TimeOfDay(hour: 18, minute: 0),
    this.activeDays = const [1, 2, 3, 4, 5],
    this.lunchBreakMinutes = 60,
    this.automationStartDate,
  });

  String toJson() {
    return jsonEncode({
      'enabled': enabled,
      'sh': start.hour, 'sm': start.minute,
      'eh': end.hour, 'em': end.minute,
      'days': activeDays,
      'lb': lunchBreakMinutes,
      'asd': automationStartDate,
    });
  }

  factory ScheduleConfig.fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return ScheduleConfig();
    try {
      final map = jsonDecode(jsonStr);
      return ScheduleConfig(
        enabled: map['enabled'] ?? false,
        start: TimeOfDay(hour: map['sh'] ?? 8, minute: map['sm'] ?? 0),
        end: TimeOfDay(hour: map['eh'] ?? 17, minute: map['em'] ?? 0),
        activeDays: List<int>.from(map['days'] ?? [1, 2, 3, 4, 5]),
        lunchBreakMinutes: map['lb'] ?? 60,
        automationStartDate: map['asd'],
      );
    } catch (e) {
      return ScheduleConfig();
    }
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hourly_rate': hourlyRate,
      'overtime_rate': overtimeRate,
      'schedule_config': scheduleConfig.toJson(),
    };
  }

  factory Azienda.fromMap(Map<String, dynamic> map) {
    return Azienda(
      id: map['id'],
      name: map['name'],
      hourlyRate: (map['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      overtimeRate: (map['overtime_rate'] as num?)?.toDouble() ?? 0.0,
      scheduleConfig: ScheduleConfig.fromJsonString(map['schedule_config']),
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