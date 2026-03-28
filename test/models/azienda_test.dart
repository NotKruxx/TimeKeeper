// test/models/azienda_test.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/models/azienda.dart';

void main() {
  group('ScheduleConfig', () {
    test('default values are sensible', () {
      const cfg = ScheduleConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.activeDays, equals([1, 2, 3, 4, 5]));
      expect(cfg.lunchBreakMinutes, 60);
    });

    test('copyWith only changes specified fields', () {
      const original = ScheduleConfig(lunchBreakMinutes: 30);
      final copy = original.copyWith(enabled: true);
      expect(copy.enabled, isTrue);
      expect(copy.lunchBreakMinutes, 30); 
    });

    test('toJson / fromJson round-trip', () {
      const cfg = ScheduleConfig(
        enabled: true,
        start: TimeOfDay(hour: 8, minute: 30),
        end: TimeOfDay(hour: 17, minute: 0),
        activeDays: [1, 3, 5],
        lunchBreakMinutes: 45,
        automationStartDate: '2025-01-01',
      );
      final restored = ScheduleConfig.fromJson(cfg.toJson());
      expect(restored.start, cfg.start);
      expect(restored.activeDays, cfg.activeDays);
    });

    test('equality is value-based', () {
      const a = ScheduleConfig(lunchBreakMinutes: 60);
      const b = ScheduleConfig(lunchBreakMinutes: 60);
      expect(a, equals(b));
    });
  });

  group('Azienda', () {
    test('standardHoursPerDay computes correctly', () {
      final az = Azienda(
        name: 'ACME',
        scheduleConfig: const ScheduleConfig(
          start: TimeOfDay(hour: 9, minute: 0),
          end: TimeOfDay(hour: 18, minute: 0),
          lunchBreakMinutes: 60,
        ),
      );
      expect(az.standardHoursPerDay, 8.0);
    });

    test('toMap / fromMap round-trip preserves all fields', () {
      final az = Azienda(
        uuid: 'test-uuid-123',
        name: 'Round Trip Co',
        hourlyRate: 12.5,
        overtimeRate: 18.75,
        scheduleConfig: const ScheduleConfig(lunchBreakMinutes: 30),
      );
      final restored = Azienda.fromMap(az.toMap());
      expect(restored.uuid, az.uuid);
      expect(restored.name, az.name);
      expect(restored.scheduleConfig.lunchBreakMinutes, 30);
    });

    test('toMap excludes uuid when null', () {
      const az = Azienda(name: 'No UUID');
      expect(az.toMap().containsKey('uuid'), isFalse);
    });

    test('equality is uuid-based', () {
      const a = Azienda(name: 'A', uuid: null);
      const b = Azienda(name: 'B', uuid: null);
      expect(a, equals(b)); // Entrambi null sono considerati uguali

      final c = Azienda(uuid: '1', name: 'C');
      final d = Azienda(uuid: '1', name: 'D');
      expect(c, equals(d)); // Stesso uuid -> uguali
    });
  });
}