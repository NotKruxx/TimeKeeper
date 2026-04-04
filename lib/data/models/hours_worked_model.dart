// lib/data/models/hours_worked_model.dart

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

@immutable
class HoursWorkedModel {
  final String uuid;
  final String userId;
  final String aziendaUuid;
  
  // REGOLA D'ORO: Queste date sono conservate ESCLUSIVAMENTE in UTC.
  final DateTime startTime;
  final DateTime endTime;
  
  final int lunchBreak;      // minuti
  final String? notes;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final String syncAction;

  const HoursWorkedModel({
    required this.uuid,
    required this.userId,
    required this.aziendaUuid,
    required this.startTime,
    required this.endTime,
    this.lunchBreak = 60,
    this.notes,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.syncAction = 'none',
  });

  // ─── factory constructor ─────────────────────────────────────────────────

  factory HoursWorkedModel.create({
    required String userId,
    required String aziendaUuid,
    required DateTime startTime,
    required DateTime endTime,
    int lunchBreak = 60,
    String? notes,
  }) {
    final now = DateTime.now().toUtc();
    return HoursWorkedModel(
      uuid: const Uuid().v4(),
      userId: userId,
      aziendaUuid: aziendaUuid,
      // Forziamo in UTC al momento della creazione
      startTime: startTime.toUtc(),
      endTime: endTime.toUtc(),
      lunchBreak: lunchBreak,
      notes: notes,
      createdAt: now,
      updatedAt: now,
      isSynced: false,
      syncAction: 'insert',
    );
  }

  // ─── computed ────────────────────────────────────────────────────────────

  /// Minuti lavorati netti (mai negativi)
  /// Essendo startTime e endTime in UTC puro, la differenza in minuti 
  /// non verrà mai sballata dal cambio dell'ora legale (DST).
  int get netMinutes {
    final total = endTime.difference(startTime).inMinutes;
    return (total - lunchBreak).clamp(0, total);
  }

  /// Ore decimali nette
  double get netHours => netMinutes / 60.0;

  bool get isDeleted => deletedAt != null;

  // ─── SQLite ──────────────────────────────────────────────────────────────

  factory HoursWorkedModel.fromSqlite(Map<String, dynamic> m) => HoursWorkedModel(
    uuid: m['uuid'] as String,
    userId: m['user_id'] as String,
    aziendaUuid: m['azienda_uuid'] as String,
    // IN LETTURA: Forziamo l'oggetto ad essere trattato come UTC
    startTime: DateTime.parse(m['start_time'] as String).toUtc(),
    endTime: DateTime.parse(m['end_time'] as String).toUtc(),
    lunchBreak: m['lunch_break'] as int? ?? 60,
    notes: m['notes'] as String?,
    deletedAt: m['deleted_at'] != null
        ? DateTime.parse(m['deleted_at'] as String).toUtc() : null,
    createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
    isSynced: (m['is_synced'] as int?) == 1,
    syncAction: m['sync_action'] as String? ?? 'none',
  );

  Map<String, dynamic> toSqlite() => {
    'uuid': uuid,
    'user_id': userId,
    'azienda_uuid': aziendaUuid,
    // IN SCRITTURA: Esportiamo sempre e solo in stringhe ISO 8601 UTC
    'start_time': startTime.toUtc().toIso8601String(),
    'end_time': endTime.toUtc().toIso8601String(),
    'lunch_break': lunchBreak,
    'notes': notes,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
    'sync_action': syncAction,
  };

  // ─── Supabase ─────────────────────────────────────────────────────────────

  factory HoursWorkedModel.fromSupabase(Map<String, dynamic> m) => HoursWorkedModel(
    uuid: m['uuid'] as String,
    userId: m['user_id'] as String,
    aziendaUuid: m['azienda_uuid'] as String,
    startTime: DateTime.parse(m['start_time'] as String).toUtc(),
    endTime: DateTime.parse(m['end_time'] as String).toUtc(),
    lunchBreak: m['lunch_break'] as int? ?? 60,
    notes: m['notes'] as String?,
    deletedAt: m['deleted_at'] != null
        ? DateTime.parse(m['deleted_at'] as String).toUtc() : null,
    createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
    isSynced: true,
    syncAction: 'none',
  );

  Map<String, dynamic> toSupabase() => {
    'uuid': uuid,
    'user_id': userId,
    'azienda_uuid': aziendaUuid,
    'start_time': startTime.toUtc().toIso8601String(),
    'end_time': endTime.toUtc().toIso8601String(),
    'lunch_break': lunchBreak,
    'notes': notes,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  // ─── copyWith ─────────────────────────────────────────────────────────────

  HoursWorkedModel copyWith({
    String? aziendaUuid,
    DateTime? startTime,
    DateTime? endTime,
    int? lunchBreak,
    String? notes,
    DateTime? deletedAt,
    bool? isSynced,
    String? syncAction,
  }) => HoursWorkedModel(
    uuid: uuid,
    userId: userId,
    aziendaUuid: aziendaUuid ?? this.aziendaUuid,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    lunchBreak: lunchBreak ?? this.lunchBreak,
    notes: notes ?? this.notes,
    deletedAt: deletedAt ?? this.deletedAt,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
    isSynced: isSynced ?? this.isSynced,
    syncAction: syncAction ?? this.syncAction,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HoursWorkedModel && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() =>
      'HoursWorkedModel(uuid: $uuid, start: ${startTime.toIso8601String()}, end: ${endTime.toIso8601String()})';
}