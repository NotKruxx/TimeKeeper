// lib/data/repositories/azienda_repository.dart

import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_provider.dart';
import '../../core/firebase/firebase_service.dart';
import '../../models/azienda.dart';

class AziendaRepository {
  AziendaRepository._();
  static final AziendaRepository instance = AziendaRepository._();

  Box<Map> get _box => HiveProvider.instance.aziende;

  // ── reads (sync — Hive è in-memory) ──────────────────────────────────────

  List<Azienda> getAll() {
    return _box.values
        .map((m) => _cast(m))
        .where((m) => m['deletedAt'] == null)
        .map((m) => Azienda.fromMap(m))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Azienda? getByUuid(String uuid) {
    final raw = _box.get(uuid);
    if (raw == null) return null;
    final m = _cast(raw);
    if (m['deletedAt'] != null) return null;
    return Azienda.fromMap(m);
  }

  // ── writes (async — Hive + schedula Firebase push) ────────────────────────

  Future<String> insert(Azienda azienda) async {
    if (getAll().any((a) => a.name == azienda.name)) return '';
    final uuid = HiveProvider.instance.generateUuid();
    final map  = azienda.copyWith(uuid: uuid).toMap();
    map['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(uuid, map);
    FirebaseService.instance.schedulePush();
    return uuid;
  }

  Future<void> update(Azienda azienda) async {
    assert(azienda.uuid != null);
    final map = azienda.toMap();
    map['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(azienda.uuid, map);
    FirebaseService.instance.schedulePush();
  }

  Future<void> delete(String uuid) async {
    final now = DateTime.now().toIso8601String();

    // Cascade soft-delete sulle ore collegate
    final hoursBox = HiveProvider.instance.hours;
    for (final key in hoursBox.keys) {
      final raw = hoursBox.get(key);
      if (raw == null) continue;
      final m = _cast(raw);
      if (m['azienda_uuid'] == uuid) {
        await hoursBox.put(key, {
          ...m,
          'deleted':   1,
          'deletedAt': now,
          'updatedAt': now,
        });
      }
    }

    // Soft-delete dell'azienda stessa (tombstone, non hard delete)
    final raw = _box.get(uuid);
    if (raw != null) {
      await _box.put(uuid, {
        ..._cast(raw),
        'deletedAt': now,
        'updatedAt': now,
      });
    }

    FirebaseService.instance.schedulePush();
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
}