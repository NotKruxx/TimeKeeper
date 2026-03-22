// test/utils/time_rounder_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/utils/time_rounder.dart';

void main() {
  DateTime dt(int h, int m) => DateTime(2025, 1, 1, h, m);

  group('roundToNearestHalfHour', () {
    test('exact hour stays unchanged',       () => expect(roundToNearestHalfHour(dt(9, 0)),  dt(9, 0)));
    test('exact half-hour stays unchanged',  () => expect(roundToNearestHalfHour(dt(9, 30)), dt(9, 30)));
    test('14 min rounds down to :00',        () => expect(roundToNearestHalfHour(dt(9, 14)), dt(9, 0)));
    test('15 min rounds up to :30',          () => expect(roundToNearestHalfHour(dt(9, 15)), dt(9, 30)));
    test('29 min rounds up to :30',          () => expect(roundToNearestHalfHour(dt(9, 29)), dt(9, 30)));
    test('44 min rounds down to :30',        () => expect(roundToNearestHalfHour(dt(9, 44)), dt(9, 30)));
    test('45 min rounds up to next :00',     () => expect(roundToNearestHalfHour(dt(9, 45)), dt(10, 0)));
    test('59 min rounds up to next :00',     () => expect(roundToNearestHalfHour(dt(9, 59)), dt(10, 0)));
    test('crosses midnight (23:45 → 00:00)', () => expect(roundToNearestHalfHour(dt(23, 45)), DateTime(2025, 1, 2, 0, 0)));
    test('seconds and milliseconds are zeroed out', () {
      final input   = DateTime(2025, 1, 1, 9, 0, 45, 999);
      final rounded = roundToNearestHalfHour(input);
      expect(rounded.second, 0);
      expect(rounded.millisecond, 0);
    });
  });
}
