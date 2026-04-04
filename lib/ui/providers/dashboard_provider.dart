// lib/ui/providers/dashboard_provider.dart

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
        // Usa sempre l'ora locale per raggruppare i mesi
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
    // Filtro per mese sull'orario locale
    final monthOk   = selectedMonth   == null || _monthKey(h.startTime.toLocal()) == selectedMonth;
    final aziendaOk = selectedAzienda == null || h.aziendaUuid == selectedAzienda!.uuid;
    return monthOk && aziendaOk;
  }).toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));

  // ─── aggregates ───────────────────────────────────────────────────────────

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
      // Calcoliamo il giorno esatto sul fuso orario dell'utente
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

  String aziendaName(String uuid) => aziendaFor(uuid)?.name ?? 'Sconosciuta';

  double ordinary(HoursWorkedModel h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return 0;
    
    // Controlliamo i giorni lavorativi (Lun=1, Dom=7)
    // ATTENZIONE AL NOME DELLA CHIAVE JSON: prima usavi 'activeDays',
    // ma in AziendaFormPage abbiamo chiamato la chiave 'work_days'!
    final activeDays = (az.scheduleConfig['work_days'] as List?)?.cast<int>() ?? [];
    
    // Controlliamo il giorno della settimana usando l'ora locale
    final isWorkDay = activeDays.contains(h.startTime.toLocal().weekday);
    if (!isWorkDay) return 0;
    
    final net = h.netHours;
    final threshold = az.standardHoursPerDay;
    return net < threshold ? net : threshold;
  }

  double overtime(HoursWorkedModel h) {
    final az = aziendaFor(h.aziendaUuid);
    if (az == null) return 0;
    
    // Stessa correzione sulla chiave del JSON
    final activeDays = (az.scheduleConfig['work_days'] as List?)?.cast<int>() ?? [];
    
    // Controlliamo il giorno della settimana usando l'ora locale
    final isWorkDay = activeDays.contains(h.startTime.toLocal().weekday);
    
    // Se non è un giorno lavorativo, è TUTTO straordinario
    if (!isWorkDay) return h.netHours;
    
    final net = h.netHours;
    final threshold = az.standardHoursPerDay;
    return net > threshold ? net - threshold : 0;
  }

  void selectAzienda(AziendaModel? az) { selectedAzienda = az; notifyListeners(); }
  void selectMonth(String? m)          { selectedMonth   = m;  notifyListeners(); }

  // Usiamo sempre questo helper passandogli una data già convertita in local
  String _monthKey(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
}