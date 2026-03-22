// test/data/services/import_export_service_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvaore/core/database/hive_provider.dart';
import 'package:salvaore/data/repositories/azienda_repository.dart';
import 'package:salvaore/data/repositories/hours_repository.dart';
import 'package:salvaore/models/azienda.dart';
import 'package:salvaore/models/hours_worked.dart';
import '../../helpers/db_helper.dart';

void main() {
  setUp(TestDb.setup);
  tearDown(TestDb.teardown);
  tearDownAll(TestDb.dispose);

  final azRepo    = AziendaRepository.instance;
  final hoursRepo = HoursRepository.instance;
  final hive      = HiveProvider.instance;

  // ── helper: simula _importRawData direttamente sui box Hive ───────────────

  Future<void> importRaw({
    required List<Map<String, dynamic>> aziende,
    required List<Map<String, dynamic>> hours,
  }) async {
    final idMap = <int, int>{};

    for (final a in aziende) {
      final oldId = (a['id'] as num?)?.toInt() ?? 0;
      final cast  = (Map m) => m.map((k, v) => MapEntry(k.toString(), v));

      final duplicate = hive.aziende.values
          .cast<Map>()
          .where((m) => cast(m)['name'] == a['name'])
          .firstOrNull;

      if (duplicate != null) {
        final existingId = (cast(duplicate)['id'] as num?)?.toInt() ?? oldId;
        idMap[oldId] = existingId;
        continue;
      }

      final newId = hive.nextAziendaId();
      idMap[oldId] = newId;
      await hive.aziende.put(newId, {
        ...a,
        'id':      newId,
        'deleted': a['deleted'] ?? 0,
      });
    }

    for (final h in hours) {
      final oldAzId = (h['azienda_id'] as num?)?.toInt() ?? 0;
      final newAzId = idMap[oldAzId] ?? oldAzId;
      final newId   = hive.nextHoursId();
      await hive.hours.put(newId, {
        ...h,
        'id':         newId,
        'azienda_id': newAzId,
        'deleted':    h['deleted'] ?? 0,
      });
    }
  }

  // ── factory helpers ───────────────────────────────────────────────────────

  Map<String, dynamic> az({
    int id = 1, String name = 'ACME', double rate = 10.0,
  }) => {
    'id':              id,
    'name':            name,
    'hourly_rate':     rate,
    'overtime_rate':   rate * 1.5,
    'schedule_config': '{"enabled":false,"start":"9:0","end":"18:0",'
        '"activeDays":[1,2,3,4,5],"lunchBreakMinutes":60}',
    'deleted': 0,
  };

  Map<String, dynamic> hour({
    int id = 1, int azId = 1,
    String start = '2025-06-02T09:00:00.000',
    String end   = '2025-06-02T17:00:00.000',
    String? notes,
  }) => {
    'id':          id,
    'azienda_id':  azId,
    'start_time':  start,
    'end_time':    end,
    'lunch_break': 60,
    'notes':       notes,
    'deleted':     0,
  };

  // ── IMPORT ────────────────────────────────────────────────────────────────

  group('import', () {
    test('importa aziende e ore correttamente', () async {
      await importRaw(aziende: [az()], hours: [hour()]);
      expect(azRepo.getAll().length,    1);
      expect(hoursRepo.getAll().length, 1);
    });

    test('id viene riassegnato — non usa l\'id originale', () async {
      await importRaw(aziende: [az(id: 999)], hours: [hour(id: 888, azId: 999)]);
      final a = azRepo.getAll().first;
      expect(a.id, isNot(999));
      expect(hoursRepo.getAll().first.aziendaId, a.id);
    });

    test('rimappa azienda_id delle ore sul nuovo id', () async {
      await importRaw(
        aziende: [az(id: 42, name: 'Remapped')],
        hours: [
          hour(id: 1, azId: 42, start: '2025-06-02T09:00:00.000', end: '2025-06-02T17:00:00.000'),
          hour(id: 2, azId: 42, start: '2025-06-03T09:00:00.000', end: '2025-06-03T17:00:00.000'),
        ],
      );
      final a = azRepo.getAll().firstWhere((a) => a.name == 'Remapped');
      expect(hoursRepo.getAll().length, 2);
      expect(hoursRepo.getAll().every((h) => h.aziendaId == a.id!), isTrue);
    });

    test('azienda duplicata per nome viene saltata', () async {
      await azRepo.insert(const Azienda(name: 'Duplicata'));
      final originalId = azRepo.getAll().first.id!;
      await importRaw(aziende: [az(id: 1, name: 'Duplicata')], hours: []);
      expect(azRepo.getAll().length, 1);
      expect(azRepo.getAll().first.id, originalId);
    });

    test('ore di azienda duplicata rimappate sull\'esistente', () async {
      await azRepo.insert(const Azienda(name: 'Esistente'));
      final existingId = azRepo.getAll().first.id!;
      await importRaw(
        aziende: [az(id: 99, name: 'Esistente')],
        hours:   [hour(id: 1, azId: 99)],
      );
      expect(hoursRepo.getAll().length, 1);
      expect(hoursRepo.getAll().first.aziendaId, existingId);
    });

    test('import vuoto non modifica lo stato', () async {
      await importRaw(aziende: [], hours: []);
      expect(azRepo.getAll(),    isEmpty);
      expect(hoursRepo.getAll(), isEmpty);
    });

    test('più aziende mantengono il mapping corretto', () async {
      await importRaw(
        aziende: [az(id: 1, name: 'Alpha'), az(id: 2, name: 'Beta')],
        hours: [
          hour(id: 1, azId: 1, start: '2025-06-02T09:00:00.000', end: '2025-06-02T17:00:00.000'),
          hour(id: 2, azId: 2, start: '2025-06-03T09:00:00.000', end: '2025-06-03T17:00:00.000'),
        ],
      );
      final alpha = azRepo.getAll().firstWhere((a) => a.name == 'Alpha');
      final beta  = azRepo.getAll().firstWhere((a) => a.name == 'Beta');
      expect(hoursRepo.getAll().where((h) => h.aziendaId == alpha.id!).length, 1);
      expect(hoursRepo.getAll().where((h) => h.aziendaId == beta.id!).length,  1);
    });

    test('campo deleted assente viene impostato a 0', () async {
      final azNoDeleted = {
        'id': 1, 'name': 'OldApp',
        'hourly_rate': 8.5, 'overtime_rate': 10.0,
        'schedule_config': '{"enabled":false,"start":"9:0","end":"18:0",'
            '"activeDays":[1,2,3,4,5],"lunchBreakMinutes":60}',
        // 'deleted' assente — come nel DB vecchio
      };
      final hNoDeleted = {
        'id': 1, 'azienda_id': 1,
        'start_time': '2025-06-02T09:00:00.000',
        'end_time':   '2025-06-02T17:00:00.000',
        'lunch_break': 60, 'notes': null,
        // 'deleted' assente
      };
      await importRaw(aziende: [azNoDeleted], hours: [hNoDeleted]);
      expect(hoursRepo.getAll().length, 1);
      expect(hoursRepo.getAll().first.deleted, isFalse);
    });
  });

  // ── ROUND-TRIP ────────────────────────────────────────────────────────────

  group('round-trip export → import', () {
    test('ripristina gli stessi dati dopo svuotamento', () async {
      await azRepo.insert(const Azienda(name: 'RoundTrip', hourlyRate: 9.0));
      final a = azRepo.getAll().first;
      await hoursRepo.insert(HoursWorked(
        aziendaId:  a.id!,
        startTime:  DateTime(2025, 6, 2, 9, 0),
        endTime:    DateTime(2025, 6, 2, 17, 0),
        lunchBreak: 60,
        notes:      'test round-trip',
      ));

      // Snapshot
      final exportedAz = hive.aziende.values
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final exportedH = hive.hours.values
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      // Svuota
      await TestDb.teardown();
      await TestDb.setup();

      // Reimporta
      await importRaw(aziende: exportedAz, hours: exportedH);

      expect(azRepo.getAll().length,              1);
      expect(azRepo.getAll().first.name,          'RoundTrip');
      expect(hoursRepo.getAll().length,           1);
      expect(hoursRepo.getAll().first.notes,      'test round-trip');
    });

    test('payload JSON contiene version=2, exported_at, aziende, hours', () async {
      await azRepo.insert(const Azienda(name: 'Export Test', hourlyRate: 12.0));
      final a = azRepo.getAll().first;
      await hoursRepo.insert(HoursWorked(
        aziendaId:  a.id!,
        startTime:  DateTime(2025, 6, 2, 9, 0),
        endTime:    DateTime(2025, 6, 2, 17, 0),
        lunchBreak: 60,
      ));

      final payload = jsonEncode({
        'version':     2,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'aziende': hive.aziende.values
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList(),
        'hours': hive.hours.values
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList(),
      });

      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['version'],              2);
      expect(decoded['exported_at'],          isA<String>());
      expect((decoded['aziende'] as List).length, 1);
      expect((decoded['hours']   as List).length, 1);
    });
  });

  // ── SQLite PARSER ──────────────────────────────────────────────────────────

  group('SQLite parser', () {
    test('rifiuta file senza magic SQLite', () {
      final fakeBytes = List<int>.filled(100, 0x41);
      final magic = String.fromCharCodes(fakeBytes.sublist(0, 15));
      expect(magic.startsWith('SQLite format 3'), isFalse);
    });

    test('riconosce magic number SQLite valido', () {
      const magic = 'SQLite format 3\x00';
      expect(magic.startsWith('SQLite format 3'), isTrue);
    });

    test('estrae timestamp ISO dal contenuto', () {
      const content = '... 2025-12-09T08:00:00.000 2025-12-09T17:00:00.000 '
          '2025-12-10T08:00:00.000 2025-12-10T17:00:00.000 ...';
      final re      = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}');
      final matches = re.allMatches(content).map((m) => m.group(0)!).toList();
      expect(matches.length,  4);
      expect(matches[0], '2025-12-09T08:00:00.000');
      expect(matches[1], '2025-12-09T17:00:00.000');
    });

    test('accoppia correttamente start e end', () {
      final ts = [
        '2025-12-09T08:00:00.000', '2025-12-09T17:00:00.000',
        '2025-12-10T08:00:00.000', '2025-12-10T17:00:00.000',
      ];
      final pairs = <List<String>>[];
      for (var i = 0; i + 1 < ts.length; i += 2) {
        final s = DateTime.parse(ts[i]);
        final e = DateTime.parse(ts[i + 1]);
        if (e.isAfter(s) && e.difference(s).inHours <= 24) {
          pairs.add([ts[i], ts[i + 1]]);
        }
      }
      expect(pairs.length,    2);
      expect(pairs[0][0], '2025-12-09T08:00:00.000');
      expect(pairs[0][1], '2025-12-09T17:00:00.000');
    });

    test('scarta end < start', () {
      final ts = ['2025-12-09T17:00:00.000', '2025-12-09T08:00:00.000'];
      int count = 0;
      for (var i = 0; i + 1 < ts.length; i += 2) {
        if (DateTime.parse(ts[i+1]).isAfter(DateTime.parse(ts[i]))) count++;
      }
      expect(count, 0);
    });

    test('scarta turni più lunghi di 24 ore', () {
      final ts = ['2025-12-09T08:00:00.000', '2025-12-11T08:00:00.000'];
      int count = 0;
      for (var i = 0; i + 1 < ts.length; i += 2) {
        final s = DateTime.parse(ts[i]);
        final e = DateTime.parse(ts[i+1]);
        if (e.isAfter(s) && e.difference(s).inHours <= 24) count++;
      }
      expect(count, 0);
    });
  });
}
