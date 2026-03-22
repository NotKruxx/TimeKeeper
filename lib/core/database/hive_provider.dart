// lib/core/database/hive_provider.dart

import 'package:hive_flutter/hive_flutter.dart';

class HiveProvider {
  HiveProvider._();
  static final HiveProvider instance = HiveProvider._();

  static const _aziende = 'aziende';
  static const _hours   = 'hours';
  static const _autoGen = 'auto_gen';
  static const _meta    = 'meta';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<Map>(_aziende),
      Hive.openBox<Map>(_hours),
      Hive.openBox<String>(_autoGen),
      Hive.openBox(_meta),
    ]);
    _initialized = true;
  }

  void injectForTesting() => _initialized = true;

  Box<Map>    get aziende => Hive.box<Map>(_aziende);
  Box<Map>    get hours   => Hive.box<Map>(_hours);
  Box<String> get autoGen => Hive.box<String>(_autoGen);
  Box         get meta    => Hive.box(_meta);

  // Usato dopo logout — pulisce tutti i dati locali
  Future<void> clearAll() async {
    await Future.wait([
      aziende.clear(),
      hours.clear(),
      autoGen.clear(),
      meta.clear(),
    ]);
  }

  int nextAziendaId() => _nextId('next_azienda_id');
  int nextHoursId()   => _nextId('next_hours_id');

  int _nextId(String key) {
    final current = (meta.get(key) as int?) ?? 0;
    final next    = current + 1;
    meta.put(key, next);
    return next;
  }
}
