import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

@immutable
class AziendaModel {
  final String uuid;
  final String userId;
  final String name;
  final double hourlyRate;
  final double overtimeRate;
  final Map<String, dynamic> scheduleConfig; // JSONB
  final double standardHoursPerDay;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final String syncAction; // 'none', 'insert', 'update', 'delete'

  const AziendaModel({
    required this.uuid,
    required this.userId,
    required this.name,
    this.hourlyRate = 0.0,
    this.overtimeRate = 0.0,
    required this.scheduleConfig,
    this.standardHoursPerDay = 8.0,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.syncAction = 'none',
  });

  // ─── SQLITE MAPS ──────────────────────────────────────────────────────────

  Map<String, dynamic> toSqlite() => {
    'uuid': uuid,
    'user_id': userId,
    'name': name,
    'hourly_rate': hourlyRate,
    'overtime_rate': overtimeRate,
    'schedule_config': jsonEncode(scheduleConfig),
    'standard_hours_per_day': standardHoursPerDay,
    'deleted_at': deletedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
    'sync_action': syncAction,
  };

  factory AziendaModel.fromSqlite(Map<String, dynamic> m) => AziendaModel(
    uuid: m['uuid'] as String,
    userId: m['user_id'] as String,
    name: m['name'] as String,
    hourlyRate: (m['hourly_rate'] as num).toDouble(),
    overtimeRate: (m['overtime_rate'] as num).toDouble(),
    scheduleConfig: jsonDecode(m['schedule_config'] as String) as Map<String, dynamic>,
    standardHoursPerDay: (m['standard_hours_per_day'] as num?)?.toDouble() ?? 8.0,
    deletedAt: m['deleted_at'] != null ? DateTime.parse(m['deleted_at'] as String) : null,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    isSynced: (m['is_synced'] as int) == 1,
    syncAction: m['sync_action'] as String,
  );

  // ─── SUPABASE MAPS ────────────────────────────────────────────────────────

  Map<String, dynamic> toSupabase() => {
    'uuid': uuid,
    'user_id': userId,
    'name': name,
    'hourly_rate': hourlyRate,
    'overtime_rate': overtimeRate,
    'schedule_config': scheduleConfig, // JSONB nativo
    'standard_hours_per_day': standardHoursPerDay,
    'deleted_at': deletedAt?.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(), // LWW
  };

  factory AziendaModel.fromSupabase(Map<String, dynamic> m) => AziendaModel(
    uuid: m['uuid'] as String,
    userId: m['user_id'] as String,
    name: m['name'] as String,
    hourlyRate: (m['hourly_rate'] as num).toDouble(),
    overtimeRate: (m['overtime_rate'] as num).toDouble(),
    scheduleConfig: m['schedule_config'] as Map<String, dynamic>,
    standardHoursPerDay: (m['standard_hours_per_day'] as num?)?.toDouble() ?? 8.0,
    deletedAt: m['deleted_at'] != null ? DateTime.parse(m['deleted_at'] as String) : null,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    isSynced: true,
    syncAction: 'none',
  );

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AziendaModel && runtimeType == other.runtimeType && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  factory AziendaModel.create({
    required String userId,
    required String name,
    double hourlyRate = 0.0,
    double overtimeRate = 0.0,
    Map<String, dynamic> scheduleConfig = const {},
  }) {
    final now = DateTime.now().toUtc();
    return AziendaModel(
      uuid: const Uuid().v4(),
      userId: userId,
      name: name,
      hourlyRate: hourlyRate,
      overtimeRate: overtimeRate,
      scheduleConfig: scheduleConfig,
      createdAt: now,
      updatedAt: now,
      isSynced: false,
      syncAction: 'insert',
    );
  }
}