// lib/ui/providers/dashboard_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../core/firebase/firebase_service.dart';
import '../../data/repositories/azienda_repository.dart';
import '../../data/repositories/hours_repository.dart';
import '../../models/azienda.dart';
import '../../models/hours_worked.dart';

class DashboardProvider extends ChangeNotifier {
  StreamSubscription? _syncSubscription;

  List<Azienda>      aziende          = [];
  List<HoursWorked>  allHours         = [];
  List<String>       availableMonths  = [];
  Azienda?           selectedAzienda;
  String?            selectedMonth;
  bool               isLoading        = false;

  // GETTER PER LA UI: Mostra il caricamento se Hive sta caricando 
  // OPPURE se Firebase sta attivamente scaricando dati la prima volta.
  bool get isReallyLoading => 
      isLoading || (allHours.isEmpty && FirebaseService.instance.isSyncing);

  DashboardProvider() {
    _syncSubscription = FirebaseService.instance.updates.listen((_) {
      load(); 
    });
    load();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  // ── filtered view ─────────────────────────────────────────────────────────

  List<HoursWorked> get filteredHours {
    return allHours.where((h) {
      final monthOk   = selectedMonth == null || _monthKey(h.startTime) == selectedMonth;
      final aziendaOk = selectedAzienda == null || h.aziendaUuid == selectedAzienda!.uuid;
      return monthOk && aziendaOk;
    }).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  // ── aggregates ────────────────────────────────────────────────────────────

  double get totalOrdinary => filteredHours.fold(0.0, (s, h) => s + ordinary(h));
  double get totalOvertime => filteredHours.fold(0.0, (s, h) => s + overtime(h));
  double get totalEarnings => filteredHours.fold(0.0, (s, h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return s;
    return s + ordinary(h) * az.hourlyRate + overtime(h) * az.overtimeRate;
  });

  Map<String, double> get hoursByDay {
    final map = <String, double>{};
    for (final h in filteredHours) {
      final key = '${h.startTime.day.toString().padLeft(2,'0')}/${h.startTime.month.toString().padLeft(2,'0')}';
      map[key] = (map[key] ?? 0) + h.netHours;
    }
    return map;
  }

  // ── public helpers ────────────────────────────────────────────────────────

  Azienda? aziendaFor(String uuid) {
    try { return aziende.firstWhere((a) => a.uuid == uuid); }
    catch (_) { return null; }
  }

  String aziendaName(String uuid) => aziendaFor(uuid)?.name ?? 'Sconosciuta';

  double ordinary(HoursWorked h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return 0;
    final net       = h.netHours;
    final isWorkDay = az.scheduleConfig.activeDays.contains(h.startTime.weekday);
    if (!isWorkDay) return 0;
    final threshold = az.standardHoursPerDay;
    return net < threshold ? net : threshold;
  }

  double overtime(HoursWorked h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return 0;
    final net       = h.netHours;
    final isWorkDay = az.scheduleConfig.activeDays.contains(h.startTime.weekday);
    if (!isWorkDay) return net;
    final threshold = az.standardHoursPerDay;
    return net > threshold ? net - threshold : 0;
  }

  // ── commands ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    isLoading = true;
    notifyListeners();

    aziende  = AziendaRepository.instance.getAll();
    allHours = HoursRepository.instance.getAll();

    final months = allHours
        .map((h) => _monthKey(h.startTime))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    availableMonths = months;

    if (selectedMonth != null && !availableMonths.contains(selectedMonth)) {
      selectedMonth = null;
    }
    if (selectedAzienda != null && !aziende.any((a) => a.uuid == selectedAzienda!.uuid)) {
      selectedAzienda = null;
    }

    selectedMonth   ??= months.isNotEmpty ? months.first : null;
    selectedAzienda ??= aziende.isNotEmpty ? aziende.first : null;

    isLoading = false;
    notifyListeners();
  }

  void selectAzienda(Azienda? az) { selectedAzienda = az; notifyListeners(); }
  void selectMonth(String? m)     { selectedMonth = m;    notifyListeners(); }

  Future<void> deleteHour(HoursWorked h) async {
    if (h.uuid == null) return;
    await HoursRepository.instance.softDelete(h.uuid!);
    await load();
  }

  String _monthKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
}