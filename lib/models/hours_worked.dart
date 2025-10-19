// lib/models/hours_worked.dart

class HoursWorked {
  final int? id;
  final int aziendaId;
  final DateTime startTime;
  final DateTime endTime;
  final int lunchBreak; // In minuti
  final String? notes;

  HoursWorked({
    this.id,
    required this.aziendaId,
    required this.startTime,
    required this.endTime,
    this.lunchBreak = 0,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'azienda_id': aziendaId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'lunch_break': lunchBreak,
      'notes': notes,
    };
  }

  factory HoursWorked.fromMap(Map<String, dynamic> map) {
    return HoursWorked(
      id: map['id'],
      aziendaId: map['azienda_id'],
      startTime: DateTime.parse(map['start_time']),
      endTime: DateTime.parse(map['end_time']),
      lunchBreak: map['lunch_break'] ?? 0,
      notes: map['notes'],
    );
  }
}
