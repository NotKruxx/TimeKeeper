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
  late String aziendaUuid;

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
    aziendaUuid = AziendaRepository.instance.getAll().first.uuid!;
  });

  tearDown(() async {
    provider.dispose();
    await TestDb.teardown();
  });
  tearDownAll(TestDb.dispose);

  Future<void> _insert(DateTime s, DateTime e, {int lunch = 60}) async {
    await HoursRepository.instance.insert(HoursWorked(
      aziendaUuid: aziendaUuid,
      startTime: s,
      endTime: e,
      lunchBreak: lunch,
    ));
  }

  group('DashboardProvider', () {
    test('load populates aziende', () async {
      await provider.load();
      expect(provider.aziende.length, 1);
    });

    test('load populates allHours', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 17, 0));
      await provider.load();
      expect(provider.allHours.length, 1);
    });

    test('totalOrdinary — 9:00-17:00 with 1h lunch = 7h ordinary', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 17, 0));
      await provider.load();
      expect(provider.totalOrdinary, closeTo(7.0, 0.01));
    });

    test('totalOvertime — 9:00-20:00 with 1h lunch = 3h overtime', () async {
      // 11h total - 1h lunch = 10h net; standard = 7h; overtime = 3h
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 20, 0));
      await provider.load();
      expect(provider.totalOvertime, closeTo(3.0, 0.01));
    });

    test('totalEarnings — 7h @ 10 + 3h @ 15 = 115', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 20, 0));
      await provider.load();
      expect(provider.totalEarnings, closeTo(115.0, 0.01));
    });

    test('deleteHour removes record and updates totals', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 17, 0));
      await provider.load();
      final target = provider.allHours.first;
      await provider.deleteHour(target);
      expect(provider.allHours, isEmpty);
      expect(provider.totalEarnings, 0.0);
    });

    test('filteredHours filters by selected azienda', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 17, 0));
      await provider.load();
      provider.selectAzienda(provider.aziende.first);
      expect(provider.filteredHours.length, 1);
    });

    test('filteredHours empty when no match for azienda', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 17, 0));
      await AziendaRepository.instance.insert(const Azienda(name: 'Other'));
      await provider.load();
      final other = provider.aziende.firstWhere((a) => a.name == 'Other');
      provider.selectAzienda(other);
      expect(provider.filteredHours, isEmpty);
    });

    test('hoursByDay aggregates correctly', () async {
      await _insert(DateTime(2025, 6, 2, 9, 0), DateTime(2025, 6, 2, 17, 0));
      await provider.load();
      final map = provider.hoursByDay;
      expect(map.values.first, closeTo(7.0, 0.01));
    });
  });
}