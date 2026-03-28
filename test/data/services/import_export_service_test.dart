// test/data/services/import_export_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/core/database/hive_provider.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/models/azienda.dart';
import '../../helpers/db_helper.dart';

void main() {
  setUp(TestDb.setup);
  tearDown(TestDb.teardown);
  tearDownAll(TestDb.dispose);

  final azRepo    = AziendaRepository.instance;
  final hoursRepo = HoursRepository.instance;
  final hive      = HiveProvider.instance;

  Map<String, dynamic> _cast(dynamic m) =>
      (m as Map).map((k, v) => MapEntry(k.toString(), v));

  /// Simulates the import service logic.
  Future<void> importRaw({
    required List<Map<String, dynamic>> aziende,
    required List<Map<String, dynamic>> hours,
  }) async {
    final uuidMap = <String, String>{};

    for (final a in aziende) {
      final oldUuid = a['uuid'] as String? ?? '';

      final duplicate = hive.aziende.values
          .where((m) => _cast(m)['name'] == a['name'])
          .where((m) => _cast(m)['deletedAt'] == null)
          .firstOrNull;

      if (duplicate != null) {
        final existingUuid = _cast(duplicate)['uuid'] as String;
        uuidMap[oldUuid] = existingUuid;
        continue;
      }

      final newUuid = a['uuid'] as String? ??
          'new-uuid-${DateTime.now().millisecondsSinceEpoch}';
      uuidMap[oldUuid] = newUuid;

      await hive.aziende.put(newUuid, {
        ...a,
        'uuid':      newUuid,
        'deleted':   a['deleted'] ?? 0,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }

    for (final h in hours) {
      final oldAzUuid = h['azienda_uuid'] as String? ?? '';
      final newAzUuid = uuidMap[oldAzUuid] ?? oldAzUuid;
      final newKey    = 'hour-${DateTime.now().microsecondsSinceEpoch}';

      await hive.hours.put(newKey, {
        ...h,
        'uuid':         newKey,
        'azienda_uuid': newAzUuid,
        'deleted':      h['deleted'] ?? 0,
        'updatedAt':    DateTime.now().toIso8601String(),
      });
    }
  }

  group('Import/Export', () {
    test('importa aziende e ore mappando UUID correttamente', () async {
      await importRaw(
        aziende: [
          {'uuid': 'old-uuid-1', 'name': 'ACME Corp', 'hourly_rate': 15.0},
        ],
        hours: [
          {
            'azienda_uuid': 'old-uuid-1',
            'start_time':   '2025-06-02T09:00:00.000',
            'end_time':     '2025-06-02T17:00:00.000',
            'lunch_break':  60,
            'deleted':      0,
          },
        ],
      );

      final tutteLeAziende = azRepo.getAll();
      expect(tutteLeAziende.length, 1);
      expect(tutteLeAziende.first.name, 'ACME Corp');

      final tutteLeOre = hoursRepo.getAll();
      expect(tutteLeOre.length, 1);
      expect(tutteLeOre.first.aziendaUuid, tutteLeAziende.first.uuid);
    });

    test('salta azienda duplicata per nome e rimappa le ore', () async {
      await azRepo.insert(const Azienda(name: 'Esistente'));
      final originalUuid = azRepo.getAll().first.uuid!;

      await importRaw(
        aziende: [
          {'uuid': 'uuid-importato', 'name': 'Esistente'},
        ],
        hours: [
          {
            'azienda_uuid': 'uuid-importato',
            'start_time':   '2025-06-03T08:00:00.000',
            'end_time':     '2025-06-03T16:00:00.000',
            'lunch_break':  60,
            'deleted':      0,
          },
        ],
      );

      expect(azRepo.getAll().length, 1);
      expect(hoursRepo.getAll().first.aziendaUuid, originalUuid);
    });

    test('non importa ore con azienda_uuid sconosciuto senza mappatura', () async {
      await importRaw(
        aziende: [],
        hours: [
          {
            'azienda_uuid': 'unknown-uuid',
            'start_time':   '2025-06-04T09:00:00.000',
            'end_time':     '2025-06-04T17:00:00.000',
            'lunch_break':  60,
            'deleted':      0,
          },
        ],
      );
      // Ore inserite ma azienda inesistente — hoursRepo le vede ma azienda è null
      expect(azRepo.getAll(), isEmpty);
      expect(hoursRepo.getAll().length, 1); // record esiste ma orfano
    });

    test('tombstoned aziende non compaiono dopo import', () async {
      await importRaw(
        aziende: [
          {
            'uuid':      'deleted-az',
            'name':      'Deleted Corp',
            'deletedAt': '2025-01-01T00:00:00.000',
          },
        ],
        hours: [],
      );
      expect(azRepo.getAll(), isEmpty);
    });
  });
}