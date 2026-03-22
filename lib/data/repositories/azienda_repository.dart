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
        .map((m) => Azienda.fromMap(_cast(m)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Azienda? getById(int id) {
    final raw = _box.get(id);
    return raw == null ? null : Azienda.fromMap(_cast(raw));
  }

  // ── writes (async — Hive + schedula Firebase push) ────────────────────────

  Future<int> insert(Azienda azienda) async {
    if (getAll().any((a) => a.name == azienda.name)) return -1;
    final id = HiveProvider.instance.nextAziendaId();
    await _box.put(id, azienda.copyWith(id: id).toMap());
    FirebaseService.instance.schedulePush();
    return id;
  }

  Future<void> update(Azienda azienda) async {
    assert(azienda.id != null);
    await _box.put(azienda.id, azienda.toMap());
    FirebaseService.instance.schedulePush();
  }

  Future<void> delete(int id) async {
    // Cascade soft-delete sulle ore
    final hoursBox = HiveProvider.instance.hours;
    for (final key in hoursBox.keys) {
      final raw = hoursBox.get(key);
      if (raw == null) continue;
      final m = _cast(raw);
      if (m['azienda_id'] == id) {
        await hoursBox.put(key, {...m, 'deleted': 1});
      }
    }
    await _box.delete(id);
    FirebaseService.instance.schedulePush();
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
}
