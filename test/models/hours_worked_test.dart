// test/models/hours_worked_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/models/hours_worked.dart';

void main() {
  final _start = DateTime(2025, 6, 1, 9, 0);
  final _end   = DateTime(2025, 6, 1, 18, 0);

  group('HoursWorked', () {
    test('netHours subtracts lunch break correctly', () {
      final h = HoursWorked(
        aziendaId: 1,
        startTime: _start,
        endTime: _end,
        lunchBreak: 60,
      );
      // 9h total - 1h break = 8h
      expect(h.netHours, 8.0);
    });

    test('netHours with zero break equals raw duration', () {
      final h = HoursWorked(
        aziendaId: 1,
        startTime: _start,
        endTime: _end,
        lunchBreak: 0,
      );
      expect(h.netHours, 9.0);
    });

    test('copyWith preserves unchanged fields', () {
      final original = HoursWorked(
        id: 1,
        aziendaId: 1,
        startTime: _start,
        endTime: _end,
        lunchBreak: 60,
        notes: 'ciao',
      );
      final copy = original.copyWith(lunchBreak: 30);
      expect(copy.lunchBreak, 30);
      expect(copy.notes, 'ciao');
      expect(copy.id, 1);
    });

    test('deleted defaults to false', () {
      final h = HoursWorked(aziendaId: 1, startTime: _start, endTime: _end);
      expect(h.deleted, isFalse);
    });

    test('toMap / fromMap round-trip preserves deleted flag', () {
      final h = HoursWorked(
        aziendaId: 1,
        startTime: _start,
        endTime: _end,
        deleted: true,
      );
      final restored = HoursWorked.fromMap(h.toMap());
      expect(restored.deleted, isTrue);
    });

    test('toMap excludes id when null', () {
      final h = HoursWorked(aziendaId: 1, startTime: _start, endTime: _end);
      expect(h.toMap().containsKey('id'), isFalse);
    });

    test('DateTime round-trips through ISO 8601 string', () {
      final h = HoursWorked(
        id: 5,
        aziendaId: 2,
        startTime: _start,
        endTime: _end,
      );
      final restored = HoursWorked.fromMap(h.toMap());
      expect(restored.startTime, _start);
      expect(restored.endTime, _end);
    });

    test('equality is id-based', () {
      final a = HoursWorked(id: 7, aziendaId: 1, startTime: _start, endTime: _end);
      final b = HoursWorked(id: 7, aziendaId: 2, startTime: _start, endTime: _end);
      expect(a, equals(b));
    });
  });
}
