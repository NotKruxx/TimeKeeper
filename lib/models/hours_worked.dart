import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

@immutable
class HoursWorked extends Equatable {
  final String? uuid;
  final String aziendaUuid;
  final DateTime startTime;
  final DateTime endTime;
  final int lunchBreak;
  final String? notes;
  final bool deleted;

  const HoursWorked({
    this.uuid,
    required this.aziendaUuid,
    required this.startTime,
    required this.endTime,
    this.lunchBreak = 0,
    this.notes,
    this.deleted = false,
  });

  double get netHours {
    final total = endTime.difference(startTime).inMinutes;
    return (total - lunchBreak) / 60.0;
  }

  HoursWorked copyWith({
    String? uuid,
    String? aziendaUuid,
    DateTime? startTime,
    DateTime? endTime,
    int? lunchBreak,
    String? notes,
    bool? deleted,
  }) => HoursWorked(
    uuid: uuid ?? this.uuid,
    aziendaUuid: aziendaUuid ?? this.aziendaUuid,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    lunchBreak: lunchBreak ?? this.lunchBreak,
    notes: notes ?? this.notes,
    deleted: deleted ?? this.deleted,
  );

  Map<String, dynamic> toMap() => {
    if (uuid != null) 'uuid': uuid,
    'azienda_uuid': aziendaUuid,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'lunch_break': lunchBreak,
    'notes': notes,
    'deleted': deleted ? 1 : 0,
  };

  factory HoursWorked.fromMap(Map<String, dynamic> m) => HoursWorked(
    uuid: m['uuid'] as String?,
    aziendaUuid: (m['azienda_uuid'] ?? m['azienda_id']?.toString() ?? '') as String,
    startTime: DateTime.parse(m['start_time'] as String),
    endTime: DateTime.parse(m['end_time'] as String),
    lunchBreak: m['lunch_break'] as int? ?? 0,
    notes: m['notes'] as String?,
    deleted: (m['deleted'] as int? ?? 0) == 1,
  );

  @override
  List<Object?> get props => [uuid, aziendaUuid, startTime, endTime, lunchBreak, notes, deleted];

  @override
  String toString() => 'HoursWorked(uuid: $uuid, aziendaUuid: $aziendaUuid, start: $startTime)';
}