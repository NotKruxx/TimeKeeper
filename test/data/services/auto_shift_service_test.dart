// test/data/services/auto_shift_service_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/data/services/auto_shift_service.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import '../../helpers/db_helper.dart';

void main() {
  setUp(TestDb.setup);
  tearDown(TestDb.teardown);
  tearDownAll(TestDb.dispose);

  final repo    = AziendaRepository.instance;
  final hours   = HoursRepository.instance;
  final service = AutoShiftService.instance;

  // ── helper ─────────────────────────────────────────────────────────────────

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> seed({
    required DateTime start,
    List<int> days = const [1, 2, 3, 4, 5],
    int startHour = 9,
    int endHour   = 17,
    int lunch     = 60,
  }) async {
    await repo.insert(Azienda(
      name: 'AutoShift Corp',
      scheduleConfig: ScheduleConfig(
        enabled:             true,
        start:               TimeOfDay(hour: startHour, minute: 0),
        end:                 TimeOfDay(hour: endHour,   minute: 0),
        activeDays:          days,
        lunchBreakMinutes:   lunch,
        automationStartDate: _iso(start),
      ),
    ));
  }

  // ── GENERAZIONE BASE ───────────────────────────────────────────────────────

  group('generazione base', () {
    test('genera turni per giorni lavorativi degli ultimi 7 giorni', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 7)));
      await service.run();
      expect(hours.getAll().length, greaterThanOrEqualTo(5));
    });

    test('i turni generati hanno orari corretti', () async {
      final start = DateTime.now().subtract(const Duration(days: 1));
      // Forza un lunedì
      final monday = start.subtract(Duration(days: start.weekday - 1));
      await seed(start: monday, startHour: 8, endHour: 16, lunch: 30);
      await service.run();

      final generated = hours.getAll()
          .where((h) => h.startTime.weekday == monday.weekday)
          .toList();

      if (generated.isNotEmpty) {
        expect(generated.first.startTime.hour, 8);
        expect(generated.first.endTime.hour,   16);
        expect(generated.first.lunchBreak,     30);
      }
    });

    test('note = "Generato automaticamente"', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 3)));
      await service.run();
      expect(
        hours.getAll().every((h) => h.notes == 'Generato automaticamente'),
        isTrue,
      );
    });

    test('non genera turni se disabled', () async {
      await repo.insert(const Azienda(name: 'Manual'));
      await service.run();
      expect(hours.getAll(), isEmpty);
    });

    test('non genera turni se automationStartDate è nel futuro', () async {
      await seed(start: DateTime.now().add(const Duration(days: 30)));
      await service.run();
      expect(hours.getAll(), isEmpty);
    });

    test('non genera più di _maxDaysBack giorni (365)', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 500)));
      await service.run();
      // Max 365 giorni × 5/7 giorni lavorativi ≈ 261 turni
      expect(hours.getAll().length, lessThanOrEqualTo(365));
    });
  });

  // ── WEEKEND / GIORNI ATTIVI ────────────────────────────────────────────────

  group('giorni attivi', () {
    test('salta sabato e domenica con config default', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 14)));
      await service.run();
      for (final h in hours.getAll()) {
        expect(h.startTime.weekday, lessThanOrEqualTo(5),
            reason: 'trovato turno nel weekend: ${h.startTime}');
      }
    });

    test('genera solo il sabato se activeDays = [6]', () async {
      await seed(
        start: DateTime.now().subtract(const Duration(days: 14)),
        days: [6],
      );
      await service.run();
      for (final h in hours.getAll()) {
        expect(h.startTime.weekday, 6,
            reason: 'turno non di sabato: ${h.startTime}');
      }
    });

    test('non genera nulla se activeDays è vuoto', () async {
      await repo.insert(Azienda(
        name: 'NoDay Corp',
        scheduleConfig: ScheduleConfig(
          enabled:             true,
          activeDays:          [],
          automationStartDate: _iso(DateTime.now().subtract(const Duration(days: 7))),
        ),
      ));
      await service.run();
      expect(hours.getAll(), isEmpty);
    });
  });

  // ── IDEMPOTENZA ───────────────────────────────────────────────────────────

  group('idempotenza', () {
    test('due run producono lo stesso numero di turni', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 7)));
      await service.run();
      final first = hours.getAll().length;
      await service.run();
      expect(hours.getAll().length, first);
    });

    test('dieci run consecutivi non duplicano', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 3)));
      await service.run();
      final first = hours.getAll().length;
      for (var i = 0; i < 9; i++) {
        await service.run();
      }
      expect(hours.getAll().length, first);
    });

    test('non genera se turno con stesso orario già esiste (inserito manualmente)', () async {
      final day = DateTime.now().subtract(const Duration(days: 1));
      // Forza lunedì
      final monday = day.subtract(Duration(days: day.weekday - 1));
      await seed(start: monday);
      final az = repo.getAll().first;

      // Inserisci manualmente un turno per lunedì
      await hours.insert(HoursWorked(
        aziendaId:  az.id!,
        startTime:  DateTime(monday.year, monday.month, monday.day, 9, 0),
        endTime:    DateTime(monday.year, monday.month, monday.day, 17, 0),
        lunchBreak: 60,
        notes:      'manuale',
      ));

      await service.run();

      // Per quel giorno deve esserci solo 1 turno
      final thatDay = hours.getAll()
          .where((h) =>
              h.startTime.year  == monday.year &&
              h.startTime.month == monday.month &&
              h.startTime.day   == monday.day)
          .toList();
      expect(thatDay.length, 1);
    });

    test('simula nuovo dispositivo: turni esistenti in Hive non vengono duplicati', () async {
      final start = DateTime.now().subtract(const Duration(days: 3));
      await seed(start: start);
      final az = repo.getAll().first;

      // Simula Firebase pull: inserisce direttamente in Hive i turni
      // come se fossero arrivati dal cloud (auto_gen box è vuoto)
      for (var i = 0; i < 3; i++) {
        final day = start.add(Duration(days: i));
        if (az.scheduleConfig.activeDays.contains(day.weekday)) {
          await hours.insert(HoursWorked(
            aziendaId:  az.id!,
            startTime:  DateTime(day.year, day.month, day.day, 9, 0),
            endTime:    DateTime(day.year, day.month, day.day, 17, 0),
            lunchBreak: 60,
            notes:      'Generato automaticamente',
          ));
        }
      }

      final beforeRun = hours.getAll().length;

      // auto_gen è vuoto → senza il fix hasOverlap(), duplicherebbe
      await service.run();

      // Non deve aver aggiunto duplicati per i giorni già presenti
      // (può aggiungerne altri se ci sono giorni non coperti)
      expect(hours.getAll().length, greaterThanOrEqualTo(beforeRun));

      // Verifica nessun duplicato per data
      final byDay = <String, int>{};
      for (final h in hours.getAll()) {
        final key = _iso(h.startTime);
        byDay[key] = (byDay[key] ?? 0) + 1;
      }
      for (final entry in byDay.entries) {
        expect(entry.value, 1,
            reason: 'duplicato trovato per il giorno ${entry.key}');
      }
    });
  });

  // ── PIÙ AZIENDE ───────────────────────────────────────────────────────────

  group('più aziende', () {
    test('genera turni separati per ogni azienda', () async {
      final start = DateTime.now().subtract(const Duration(days: 3));

      await repo.insert(Azienda(
        name: 'Azienda A',
        scheduleConfig: ScheduleConfig(
          enabled: true, activeDays: [1,2,3,4,5],
          automationStartDate: _iso(start),
        ),
      ));
      await repo.insert(Azienda(
        name: 'Azienda B',
        scheduleConfig: ScheduleConfig(
          enabled: true, activeDays: [1,2,3,4,5],
          automationStartDate: _iso(start),
        ),
      ));

      await service.run();

      final azA = repo.getAll().firstWhere((a) => a.name == 'Azienda A');
      final azB = repo.getAll().firstWhere((a) => a.name == 'Azienda B');

      expect(hours.getByAzienda(azA.id!), isNotEmpty);
      expect(hours.getByAzienda(azB.id!), isNotEmpty);

      // I turni delle due aziende non si mescolano
      for (final h in hours.getByAzienda(azA.id!)) {
        expect(h.aziendaId, azA.id);
      }
      for (final h in hours.getByAzienda(azB.id!)) {
        expect(h.aziendaId, azB.id);
      }
    });

    test('azienda senza schedule non interferisce con le altre', () async {
      final start = DateTime.now().subtract(const Duration(days: 3));

      await repo.insert(const Azienda(name: 'Manual'));
      await repo.insert(Azienda(
        name: 'Auto',
        scheduleConfig: ScheduleConfig(
          enabled: true, activeDays: [1,2,3,4,5],
          automationStartDate: _iso(start),
        ),
      ));

      await service.run();

      final manual = repo.getAll().firstWhere((a) => a.name == 'Manual');
      expect(hours.getByAzienda(manual.id!), isEmpty);
    });
  });
}
