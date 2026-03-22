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

  final _aziendaRepo = AziendaRepository.instance;
  final _hoursRepo   = HoursRepository.instance;
  final _service     = AutoShiftService.instance;

  Future<void> _seed({required DateTime start, List<int> days = const [1,2,3,4,5]}) async {
    final d = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
    await _aziendaRepo.insert(Azienda(
      name: 'AutoShift Corp',
      scheduleConfig: ScheduleConfig(
        enabled: true,
        start: const TimeOfDay(hour: 9, minute: 0),
        end:   const TimeOfDay(hour: 17, minute: 0),
        activeDays: days,
        lunchBreakMinutes: 60,
        automationStartDate: d,
      ),
    ));
  }

  group('AutoShiftService', () {
    test('genera turni per giorni lavorativi', () async {
      await _seed(start: DateTime.now().subtract(const Duration(days: 7)));
      await _service.run();
      expect(_hoursRepo.getAll().length, greaterThanOrEqualTo(5));
    });

    test('idempotente — due run stesso conteggio', () async {
      await _seed(start: DateTime.now().subtract(const Duration(days: 7)));
      await _service.run();
      final first = _hoursRepo.getAll().length;
      await _service.run();
      expect(_hoursRepo.getAll().length, first);
    });

    test('salta weekend', () async {
      await _seed(start: DateTime.now().subtract(const Duration(days: 7)));
      await _service.run();
      for (final h in _hoursRepo.getAll()) {
        expect(h.startTime.weekday, lessThanOrEqualTo(5));
      }
    });

    test('niente turni se disabled', () async {
      await _aziendaRepo.insert(const Azienda(name: 'Manual'));
      await _service.run();
      expect(_hoursRepo.getAll(), isEmpty);
    });

    test('niente turni se start nel futuro', () async {
      await _seed(start: DateTime.now().add(const Duration(days: 30)));
      await _service.run();
      expect(_hoursRepo.getAll(), isEmpty);
    });

    test('note corrette sui turni generati', () async {
      await _seed(start: DateTime.now().subtract(const Duration(days: 3)));
      await _service.run();
      expect(_hoursRepo.getAll().every((h) => h.notes == 'Generato automaticamente'), isTrue);
    });

    test('non genera se turno sovrapposto esiste', () async {
      final start = DateTime.now().subtract(const Duration(days: 1));
      await _seed(start: start);
      final az    = _aziendaRepo.getAll().first;
      await _hoursRepo.insert(HoursWorked(
        aziendaId:  az.id!,
        startTime:  DateTime(start.year, start.month, start.day, 9, 0),
        endTime:    DateTime(start.year, start.month, start.day, 17, 0),
        lunchBreak: 60,
        notes:      'manual',
      ));
      await _service.run();
      expect(_hoursRepo.getAll().where((h) => h.startTime.day == start.day).length, 1);
    });
  });
}
