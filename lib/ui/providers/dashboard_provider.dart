import 'package:flutter/foundation.dart';
import '../../data/models/azienda_model.dart';
import '../../data/models/hours_worked_model.dart';
import 'data_cache_provider.dart';

class DashboardProvider extends ChangeNotifier {
  List<AziendaModel>     aziende         = [];
  List<HoursWorkedModel> allHours        = [];
  List<String>           availableMonths = [];
  AziendaModel?          selectedAzienda;
  String?                selectedMonth;
  bool                   isLoading       = false;
  String?                error;

  void updateFromCache(DataCacheProvider cache) {
    aziende = cache.aziende;
    allHours = cache.hours;
    isLoading = cache.isLoading;
    _computeMonths();
    notifyListeners();
  }

  void _computeMonths() {
    final months = allHours
        .map((h) => _monthKey(h.startTime.toLocal()))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    availableMonths = months;

    if (selectedMonth != null && !availableMonths.contains(selectedMonth)) {
      selectedMonth = null;
    }
    selectedMonth ??= months.isNotEmpty ? months.first : null;
  }

  // ─── filtered view ────────────────────────────────────────────────────────

  List<HoursWorkedModel> get filteredHours => allHours.where((h) {
    final monthOk   = selectedMonth   == null || _monthKey(h.startTime.toLocal()) == selectedMonth;
    final aziendaOk = selectedAzienda == null || h.aziendaUuid == selectedAzienda!.uuid;
    return monthOk && aziendaOk;
  }).toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));

  // ─── aggregates ───────────────────────────────────────────────────────────

  double get totalOrdinary =>
      filteredHours.fold(0.0, (s, h) => s + ordinary(h));

  double get totalOvertime =>
      filteredHours.fold(0.0, (s, h) => s + overtime(h));

  double get totalEarnings =>
      filteredHours.fold(0.0, (s, h) {
        final az = aziendaFor(h.aziendaUuid);
        if (az == null) return s;
        return s +
            ordinary(h) * az.hourlyRate +
            overtime(h) * az.overtimeRate;
      });

  Map<String, double> get hoursByDay {
    final map = <String, double>{};
    for (final h in filteredHours) {
      final localTime = h.startTime.toLocal();
      final key =
          '${localTime.day.toString().padLeft(2, '0')}/${localTime.month.toString().padLeft(2, '0')}';

      map[key] = (map[key] ?? 0) + h.netHours;
    }
    return map;
  }

  // ─── helpers ──────────────────────────────────────────────────────────────

  AziendaModel? aziendaFor(String uuid) {
    try {
      return aziende.firstWhere((a) => a.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  String aziendaName(String uuid) =>
      aziendaFor(uuid)?.name ?? 'Sconosciuta';

  double ordinary(HoursWorkedModel h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return 0;

    final activeDays =
        (az.scheduleConfig['work_days'] as List?)?.cast<int>() ?? [];

    final weekday = h.startTime.toLocal().weekday;
    final isWorkDay = activeDays.contains(weekday);

    final net = _safeNetHours(h);

    debugPrint('--- ORDINARY DEBUG ---');
    debugPrint('Day: $weekday | WorkDay: $isWorkDay');
    debugPrint('Net hours: $net');

    if (!isWorkDay) return 0;

    final threshold = az.standardHoursPerDay;
    return net < threshold ? net : threshold;
  }

  double overtime(HoursWorkedModel h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return 0;

    final activeDays =
        (az.scheduleConfig['work_days'] as List?)?.cast<int>() ?? [];

    final weekday = h.startTime.toLocal().weekday;
    final isWorkDay = activeDays.contains(weekday);

    final net = _safeNetHours(h);

    debugPrint('--- OVERTIME DEBUG ---');
    debugPrint('Day: $weekday | WorkDay: $isWorkDay');
    debugPrint('Net hours: $net');

    // Sabato/domenica → tutto straordinario
    if (!isWorkDay) return net;

    final threshold = az.standardHoursPerDay;
    return net > threshold ? net - threshold : 0;
  }

  /// 🔥 FIX: protezione contro netHours sballato
  double _safeNetHours(HoursWorkedModel h) {
    final start = h.startTime.toLocal();
    final end = h.endTime.toLocal();

    final minutes = end.difference(start).inMinutes;
    final netMinutes = minutes - h.lunchBreak;

    final result = netMinutes / 60.0;

    debugPrint('--- NET HOURS DEBUG ---');
    debugPrint('Start: $start');
    debugPrint('End: $end');
    debugPrint('Minutes: $minutes');
    debugPrint('Lunch: ${h.lunchBreak}');
    debugPrint('Net calc: $result');
    debugPrint('Model netHours: ${h.netHours}');

    return result;
  }

  void selectAzienda(AziendaModel? az) {
    selectedAzienda = az;
    notifyListeners();
  }

  void selectMonth(String? m) {
    selectedMonth = m;
    notifyListeners();
  }

  String _monthKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
}