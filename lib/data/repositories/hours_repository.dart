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

  List<HoursWorked> getByAzienda(String aziendaUuid) =>
      getAll().where((h) => h.aziendaUuid == aziendaUuid).toList();

  bool hasOverlap(HoursWorked hours) {
    return getAll().any((e) {
      if (e.aziendaUuid != hours.aziendaUuid) return false;
      if (e.uuid != null && e.uuid == hours.uuid) return false;
      return e.startTime.isBefore(hours.endTime) &&
             e.endTime.isAfter(hours.startTime);
    });
  }

  // ── writes ────────────────────────────────────────────────────────────────

  Future<String> insert(HoursWorked hours) async {
    final uuid = hours.uuid ?? HiveProvider.instance.generateUuid();
    final map  = hours.copyWith(uuid: uuid).toMap();
    map['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(uuid, map);
    FirebaseService.instance.schedulePush();
    return uuid;
  }

  Future<void> update(HoursWorked hours) async {
    assert(hours.uuid != null);
    final map = hours.toMap();
    map['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(hours.uuid, map);
    FirebaseService.instance.schedulePush();
  }

  Future<void> softDelete(String uuid) async {
    final raw = _box.get(uuid);
    if (raw == null) return;
    final now = DateTime.now().toIso8601String();
    await _box.put(uuid, {
      ..._cast(raw),
      'deleted':   1,
      'deletedAt': now,
      'updatedAt': now,
    });
    FirebaseService.instance.schedulePush();
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
}