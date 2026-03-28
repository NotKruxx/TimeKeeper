import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/models/hours_worked.dart';

void main() {
  group('HoursWorked Model Tests', () {
    final startTime = DateTime(2024, 1, 1, 9, 0);
    final endTime = DateTime(2024, 1, 1, 18, 0);

    test('should calculate netHours correctly (9h - 30min break)', () {
      final hours = HoursWorked(
        uuid: 'test-uuid-123',
        aziendaUuid: 'azienda-abc',
        startTime: startTime,
        endTime: endTime,
        lunchBreak: 30,
      );

      // (9 ore * 60 - 30) / 60 = 8.5
      expect(hours.netHours, 8.5);
    });

    test('fromMap should handle uuid and azienda_uuid', () {
      final map = {
        'uuid': '12345',
        'azienda_uuid': 'comp-99',
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'lunch_break': 60,
        'deleted': 0,
      };

      final result = HoursWorked.fromMap(map);

      expect(result.uuid, '12345');
      expect(result.aziendaUuid, 'comp-99');
      expect(result.lunchBreak, 60);
    });

    test('toMap should contain uuid string', () {
      final hours = HoursWorked(
        uuid: 'abc-def',
        aziendaUuid: 'ghi',
        startTime: startTime,
        endTime: endTime,
      );

      final map = hours.toMap();

      expect(map['uuid'], 'abc-def');
      expect(map['azienda_uuid'], 'ghi');
    });
  });
}