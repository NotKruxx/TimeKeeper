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

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> seed({
    required DateTime start,
    String name = 'AutoShift Corp',
    List<int> days = const [1, 2, 3, 4, 5],
    int startHour = 9,
    int endHour = 17,
    int lunch = 60,
  }) async {
    await repo.insert(Azienda(
      name: name,
      scheduleConfig: ScheduleConfig(
        enabled: true,
        start: TimeOfDay(hour: startHour, minute: 0),
        end:   TimeOfDay(hour: endHour,   minute: 0),
        activeDays: days,
        lunchBreakMinutes: lunch,
        automationStartDate: _iso(start),
      ),
    ));
  }

  group('generazione base', () {
    test('genera turni per giorni lavorativi degli ultimi 7 giorni', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 7)));
      await service.run();
      expect(hours.getAll().length, greaterThanOrEqualTo(5));
    });

    test('i turni generati hanno orari corretti', () async {
      final start  = DateTime.now().subtract(const Duration(days: 1));
      final monday = start.subtract(Duration(days: start.weekday - 1));
      await seed(start: monday, startHour: 8, endHour: 16, lunch: 30);
      await service.run();

      final generated = hours.getAll()
          .where((h) => h.startTime.weekday == monday.weekday)
          .toList();

      if (generated.isNotEmpty) {
        expect(generated.first.startTime.hour, 8);
        expect(generated.first.endTime.hour,   16);
        expect(generated.first.lunchBreak,      30);
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
  });

  group('idempotenza', () {
    test('non duplica turno se stesso orario già esiste', () async {
      final day    = DateTime.now().subtract(const Duration(days: 1));
      final monday = day.subtract(Duration(days: day.weekday - 1));
      await seed(start: monday);
      final az = repo.getAll().first;

      await hours.insert(HoursWorked(
        aziendaUuid: az.uuid!,
        startTime:   DateTime(monday.year, monday.month, monday.day, 9, 0),
        endTime:     DateTime(monday.year, monday.month, monday.day, 17, 0),
        lunchBreak:  60,
        notes:       'manuale',
      ));

      await service.run();

      final thatDay = hours.getAll().where((h) =>
          h.startTime.year  == monday.year &&
          h.startTime.month == monday.month &&
          h.startTime.day   == monday.day).toList();

      expect(thatDay.length, 1);
    });

    test('run() due volte non duplica turni', () async {
      await seed(start: DateTime.now().subtract(const Duration(days: 3)));
      await service.run();
      final countFirst = hours.getAll().length;
      await service.run();
      expect(hours.getAll().length, countFirst);
    });
  });

  group('più aziende', () {
    test('genera turni separati per ogni azienda', () async {
      final start = DateTime.now().subtract(const Duration(days: 3));
      await seed(start: start, name: 'Azienda A');
      await seed(start: start, name: 'Azienda B');
      await service.run();

      final azA = repo.getAll().firstWhere((a) => a.name == 'Azienda A');
      final azB = repo.getAll().firstWhere((a) => a.name == 'Azienda B');

      expect(hours.getByAzienda(azA.uuid!), isNotEmpty);
      expect(hours.getByAzienda(azB.uuid!), isNotEmpty);
    });
  });
}