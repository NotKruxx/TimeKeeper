// lib/core/database/hive_provider.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class HiveProvider {
  HiveProvider._();
  static final HiveProvider instance = HiveProvider._();

  static const _aziende = 'aziende';
  static const _hours   = 'hours';
  static const _autoGen = 'auto_gen';
  static const _meta    = 'meta';

  static const _uuid = Uuid();

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
    await _migrateToUuid();
  }

  void injectForTesting() => _initialized = true;

  Box<Map>    get aziende => Hive.box<Map>(_aziende);
  Box<Map>    get hours   => Hive.box<Map>(_hours);
  Box<String> get autoGen => Hive.box<String>(_autoGen);
  Box         get meta    => Hive.box(_meta);

  /// Genera un nuovo UUID v4.
  String generateUuid() => _uuid.v4();

  /// Migrazione one-shot: assegna uuid a tutti i record che ne sono privi.
  /// Costruisce anche una mappa oldIntId → newUuid per rimappare azienda_id nelle ore.
  Future<void> _migrateToUuid() async {
    final alreadyMigrated = meta.get('uuid_migration_done') as bool? ?? false;
    if (alreadyMigrated) return;

    // ── 1. Migra aziende ──────────────────────────────────────────────────
    final azBox  = aziende;
    final idMap  = <String, String>{}; // vecchio int id (come stringa) → nuovo uuid

    final azEntries = azBox.toMap();
    for (final entry in azEntries.entries) {
      final raw = Map<String, dynamic>.from(
        (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
      );

      // Se ha già un uuid valido saltiamo
      if (raw['uuid'] != null && (raw['uuid'] as String).length == 36) {
        idMap[entry.key.toString()] = raw['uuid'] as String;
        continue;
      }

      final newUuid = _uuid.v4();
      idMap[entry.key.toString()] = newUuid;

      raw['uuid']      = newUuid;
      raw['updatedAt'] = raw['updatedAt'] ?? DateTime.now().toIso8601String();

      await azBox.delete(entry.key);
      await azBox.put(newUuid, raw);
    }

    // ── 2. Migra hours ─────────────────────────────────────────────────────
    final hBox = hours;
    final hEntries = hBox.toMap();

    for (final entry in hEntries.entries) {
      final raw = Map<String, dynamic>.from(
        (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
      );

      if (raw['uuid'] != null && (raw['uuid'] as String).length == 36) continue;

      final newUuid = _uuid.v4();

      // Rimappa azienda_id → azienda_uuid
      final oldAzId   = raw['azienda_id']?.toString() ?? '';
      final azUuid    = idMap[oldAzId] ?? oldAzId;

      raw['uuid']        = newUuid;
      raw['azienda_uuid'] = azUuid;
      raw['updatedAt']   = raw['updatedAt'] ?? DateTime.now().toIso8601String();

      await hBox.delete(entry.key);
      await hBox.put(newUuid, raw);
    }

    await meta.put('uuid_migration_done', true);
  }

  // Usato dopo logout — pulisce tutti i dati locali
  Future<void> clearAll() async {
    await Future.wait([
      aziende.clear(),
      hours.clear(),
      autoGen.clear(),
      meta.clear(),
    ]);
  }
}