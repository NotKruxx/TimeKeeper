// lib/data/repositories/hours_repository.dart

import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_provider.dart';
import '../../core/firebase/firebase_service.dart';
import '../../models/hours_worked.dart';

class HoursRepository {
  HoursRepository._();
  static final HoursRepository instance = HoursRepository._();

  Box<Map> get _box => HiveProvider.instance.hours;

  // ── reads ─────────────────────────────────────────────────────────────────

  List<HoursWorked> getAll() {
    return _box.values
        .map((m) => HoursWorked.fromMap(_cast(m)))
        .where((h) => !h.deleted)
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  List<HoursWorked> getByAzienda(int aziendaId) =>
      getAll().where((h) => h.aziendaId == aziendaId).toList();

  bool hasOverlap(HoursWorked hours) {
    return getAll().any((e) {
      if (e.aziendaId != hours.aziendaId) return false;
      if (e.id != null && e.id == hours.id) return false;
      return e.startTime.isBefore(hours.endTime) &&
             e.endTime.isAfter(hours.startTime);
    });
  }

  // ── writes ────────────────────────────────────────────────────────────────

  Future<int> insert(HoursWorked hours) async {
    final id = hours.id ?? HiveProvider.instance.nextHoursId();
    await _box.put(id, hours.copyWith(id: id).toMap());
    FirebaseService.instance.schedulePush();
    return id;
  }

  Future<void> update(HoursWorked hours) async {
    assert(hours.id != null);
    await _box.put(hours.id, hours.toMap());
    FirebaseService.instance.schedulePush();
  }

  Future<void> softDelete(int id) async {
    final raw = _box.get(id);
    if (raw == null) return;
    await _box.put(id, {..._cast(raw), 'deleted': 1});
    FirebaseService.instance.schedulePush();
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
}
