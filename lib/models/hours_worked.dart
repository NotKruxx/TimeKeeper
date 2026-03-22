// lib/models/hours_worked.dart

import 'package:flutter/foundation.dart';

@immutable
class HoursWorked {
  final int? id;
  final int aziendaId;
  final DateTime startTime;
  final DateTime endTime;
  final int lunchBreak; // minutes
  final String? notes;
  final bool deleted;  // soft-delete — never hard-delete records

  const HoursWorked({
    this.id,
    required this.aziendaId,
    required this.startTime,
    required this.endTime,
    this.lunchBreak = 0,
    this.notes,
    this.deleted = false,
  });

  /// Net worked hours, lunch break excluded.
  double get netHours {
    final total = endTime.difference(startTime).inMinutes;
    return (total - lunchBreak) / 60.0;
  }

  HoursWorked copyWith({
    int? id,
    int? aziendaId,
    DateTime? startTime,
    DateTime? endTime,
    int? lunchBreak,
    String? notes,
    bool? deleted,
  }) => HoursWorked(
    id: id ?? this.id,
    aziendaId: aziendaId ?? this.aziendaId,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    lunchBreak: lunchBreak ?? this.lunchBreak,
    notes: notes ?? this.notes,
    deleted: deleted ?? this.deleted,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'azienda_id': aziendaId,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'lunch_break': lunchBreak,
    'notes': notes,
    'deleted': deleted ? 1 : 0,
  };

  factory HoursWorked.fromMap(Map<String, dynamic> m) => HoursWorked(
    id: m['id'] as int?,
    aziendaId: m['azienda_id'] as int,
    startTime: DateTime.parse(m['start_time'] as String),
    endTime: DateTime.parse(m['end_time'] as String),
    lunchBreak: m['lunch_break'] as int? ?? 0,
    notes: m['notes'] as String?,
    deleted: (m['deleted'] as int? ?? 0) == 1,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is HoursWorked && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HoursWorked(id: $id, aziendaId: $aziendaId, start: $startTime)';
}
