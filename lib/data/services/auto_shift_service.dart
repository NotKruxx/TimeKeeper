// lib/data/services/auto_shift_service.dart

import '../../core/database/hive_provider.dart';
import '../../data/repositories/azienda_repository.dart';
import '../../data/repositories/hours_repository.dart';
import '../../models/hours_worked.dart';

class AutoShiftService {
  AutoShiftService._();
  static final AutoShiftService instance = AutoShiftService._();

  static const int _maxDaysBack = 365;

  Future<void> run() async {
    final aziende = AziendaRepository.instance.getAll();
    final today   = _dateOnly(DateTime.now());

    for (final azienda in aziende) {
      final config = azienda.scheduleConfig;
      if (!config.enabled ||
          config.automationStartDate == null ||
          azienda.id == null) { continue; }

      final startDate = DateTime.tryParse(config.automationStartDate!);
      if (startDate == null) continue;

      final daysDiff      = today.difference(_dateOnly(startDate)).inDays;
      if (daysDiff < 0) continue;
      final daysToProcess = daysDiff.clamp(0, _maxDaysBack);

      final autoGenBox = HiveProvider.instance.autoGen;

      for (var i = 0; i <= daysToProcess; i++) {
        final date    = startDate.add(Duration(days: i));
        final dateKey = '${azienda.id}|${_isoDate(date)}';

        // Idempotency guard
        if (autoGenBox.values.contains(dateKey)) continue;

        if (config.activeDays.contains(date.weekday)) {
          final start = DateTime(date.year, date.month, date.day,
              config.start.hour, config.start.minute);
          final end = DateTime(date.year, date.month, date.day,
              config.end.hour, config.end.minute);

          final shift = HoursWorked(
            aziendaId:  azienda.id!,
            startTime:  start,
            endTime:    end,
            lunchBreak: config.lunchBreakMinutes,
            notes:      'Generato automaticamente',
          );

          if (!HoursRepository.instance.hasOverlap(shift)) {
            await HoursRepository.instance.insert(shift);
          }
        }

        await autoGenBox.add(dateKey);
      }
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _isoDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
