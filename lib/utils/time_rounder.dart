// lib/utils/time_rounder.dart

DateTime roundToNearestHalfHour(DateTime dateTime) {
  int minutes = dateTime.minute;
  if (minutes == 0 || minutes == 30) {
    return DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      minutes,
    );
  }
  if (minutes > 0 && minutes < 30) {
    if (minutes <= 15) {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        0,
      );
    } else {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        30,
      );
    }
  } else {
    if (minutes <= 45) {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        30,
      );
    } else {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour + 1,
        0,
      );
    }
  }
}
