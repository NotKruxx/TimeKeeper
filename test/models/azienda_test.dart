// test/models/azienda_test.dart
//
// Pure unit tests — no DB, no Flutter, no async.
// Models are plain Dart objects; these tests run in milliseconds.

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
      expect(copy.lunchBreakMinutes, 30); // unchanged
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
      expect(restored.enabled, cfg.enabled);
      expect(restored.start, cfg.start);
      expect(restored.end, cfg.end);
      expect(restored.activeDays, cfg.activeDays);
      expect(restored.lunchBreakMinutes, cfg.lunchBreakMinutes);
      expect(restored.automationStartDate, cfg.automationStartDate);
    });

    test('fromJson tolerates missing fields gracefully', () {
      final cfg = ScheduleConfig.fromJson({});
      expect(cfg.enabled, isFalse);
      expect(cfg.activeDays, equals([1, 2, 3, 4, 5]));
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
      // (18:00 - 09:00) - 60 min = 480 min = 8 h
      expect(az.standardHoursPerDay, 8.0);
    });

    test('standardHoursPerDay falls back to 8h when config is zero/negative', () {
      final az = Azienda(
        name: 'Bad Config',
        scheduleConfig: const ScheduleConfig(
          start: TimeOfDay(hour: 18, minute: 0),
          end: TimeOfDay(hour: 9, minute: 0), // end < start
        ),
      );
      expect(az.standardHoursPerDay, 8.0);
    });

    test('copyWith produces a new instance with updated fields', () {
      const original = Azienda(name: 'Old', hourlyRate: 10.0);
      final updated = original.copyWith(name: 'New', hourlyRate: 15.0);
      expect(updated.name, 'New');
      expect(updated.hourlyRate, 15.0);
      expect(original.name, 'Old'); // original is untouched
    });

    test('toMap / fromMap round-trip preserves all fields', () {
      final az = Azienda(
        id: 1,
        name: 'Round Trip Co',
        hourlyRate: 12.5,
        overtimeRate: 18.75,
        scheduleConfig: const ScheduleConfig(lunchBreakMinutes: 30),
      );
      final restored = Azienda.fromMap(az.toMap());
      expect(restored.id, az.id);
      expect(restored.name, az.name);
      expect(restored.hourlyRate, az.hourlyRate);
      expect(restored.overtimeRate, az.overtimeRate);
      expect(restored.scheduleConfig.lunchBreakMinutes, 30);
    });

    test('toMap excludes id when null (for INSERT)', () {
      const az = Azienda(name: 'No ID');
      expect(az.toMap().containsKey('id'), isFalse);
    });

    test('equality is id-based', () {
      const a = Azienda(name: 'A');       // id = null
      const b = Azienda(name: 'B');       // id = null
      // Both null → equal (same "no id" identity)
      expect(a, equals(b));

      final c = Azienda(id: 1, name: 'C');
      final d = Azienda(id: 1, name: 'D');
      expect(c, equals(d)); // same id → equal regardless of name
    });

    test('schedule_config JSON survives double-encode cycle', () {
      final az = Azienda(
        id: 42,
        name: 'Encode Test',
        scheduleConfig: const ScheduleConfig(
          enabled: true,
          lunchBreakMinutes: 20,
        ),
      );
      final map = az.toMap();
      // schedule_config is stored as a JSON string in the map
      expect(map['schedule_config'], isA<String>());
      final decoded = jsonDecode(map['schedule_config'] as String);
      expect(decoded['lunchBreakMinutes'], 20);
    });
  });
}
