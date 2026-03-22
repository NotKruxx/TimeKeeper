// test/ui/providers/dashboard_provider_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import 'package:salvaore/ui/providers/dashboard_provider.dart';
import '../../helpers/db_helper.dart';

void main() {
  late DashboardProvider provider;
  late int               aziendaId;

  setUp(() async {
    await TestDb.setup();
    provider = DashboardProvider();
    await AziendaRepository.instance.insert(Azienda(
      name: 'Test Corp',
      hourlyRate: 10.0,
      overtimeRate: 15.0,
      scheduleConfig: const ScheduleConfig(
        start: TimeOfDay(hour: 9, minute: 0),
        end:   TimeOfDay(hour: 17, minute: 0),
        lunchBreakMinutes: 60,
        activeDays: [1, 2, 3, 4, 5],
      ),
    ));
    aziendaId = AziendaRepository.instance.getAll().first.id!;
  });

  tearDown(() async {
    provider.dispose();
    await TestDb.teardown();
  });
  tearDownAll(TestDb.dispose);

  Future<void> _insert(DateTime s, DateTime e, {int lunch = 60}) async {
    await HoursRepository.instance.insert(HoursWorked(
      aziendaId: aziendaId, startTime: s, endTime: e, lunchBreak: lunch,
    ));
  }

  group('DashboardProvider', () {
    test('load populates aziende and allHours', () async {
      await _insert(DateTime(2025,6,2,9,0), DateTime(2025,6,2,17,0));
      await provider.load();
      expect(provider.aziende.length, 1);
      expect(provider.allHours.length, 1);
    });

    test('selectedMonth defaults to most recent', () async {
      await _insert(DateTime(2025,5,1,9,0), DateTime(2025,5,1,17,0));
      await _insert(DateTime(2025,6,1,9,0), DateTime(2025,6,1,17,0));
      await provider.load();
      expect(provider.selectedMonth, '2025-06');
    });

    test('filteredHours respects selectedMonth', () async {
      await _insert(DateTime(2025,5,1,9,0), DateTime(2025,5,1,17,0));
      await _insert(DateTime(2025,6,1,9,0), DateTime(2025,6,1,17,0));
      await provider.load();
      provider.selectMonth('2025-05');
      expect(provider.filteredHours.length, 1);
      expect(provider.filteredHours.first.startTime.month, 5);
    });

    test('totalOrdinary — standard day = 7h', () async {
      await _insert(DateTime(2025,6,2,9,0), DateTime(2025,6,2,17,0));
      await provider.load();
      expect(provider.totalOrdinary, closeTo(7.0, 0.01));
    });

    test('totalOvertime — extra hours', () async {
      await _insert(DateTime(2025,6,2,9,0), DateTime(2025,6,2,20,0));
      await provider.load();
      expect(provider.totalOvertime, closeTo(3.0, 0.01));
    });

    test('totalEarnings — 7h@10 + 3h@15 = 115', () async {
      await _insert(DateTime(2025,6,2,9,0), DateTime(2025,6,2,20,0));
      await provider.load();
      expect(provider.totalEarnings, closeTo(115.0, 0.01));
    });

    test('weekend shift = all overtime', () async {
      await _insert(DateTime(2025,6,7,9,0), DateTime(2025,6,7,17,0)); // Saturday
      await provider.load();
      expect(provider.totalOrdinary, closeTo(0.0, 0.01));
      expect(provider.totalOvertime, closeTo(7.0, 0.01));
    });

    test('deleteHour removes record', () async {
      await _insert(DateTime(2025,6,2,9,0), DateTime(2025,6,2,17,0));
      await provider.load();
      await provider.deleteHour(provider.allHours.first);
      expect(provider.allHours, isEmpty);
    });

    test('notifyListeners called on load', () async {
      int count = 0;
      provider.addListener(() => count++);
      await provider.load();
      expect(count, greaterThan(0));
    });
  });
}
