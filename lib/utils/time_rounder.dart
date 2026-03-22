// lib/utils/time_rounder.dart
//
// Rounds a DateTime to the nearest 30-minute boundary.
// Pure function — no side effects, trivially testable.

DateTime roundToNearestHalfHour(DateTime dt) {
  final excess   = dt.minute % 30;
  final roundUp  = excess >= 15;
  final rounded  = dt.subtract(Duration(minutes: dt.minute, seconds: dt.second, milliseconds: dt.millisecond))
                     .add(Duration(minutes: roundUp ? dt.minute - excess + 30 : dt.minute - excess));
  return rounded;
}
