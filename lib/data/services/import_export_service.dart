// lib/data/services/import_export_service.dart
//
// Export → JSON
// Import → JSON (tutte le piattaforme) oppure .db SQLite vecchio (web: parsing binario)
//
// Struttura JSON:
// {
//   "version": 3,
//   "exported_at": "...",
//   "aziende": [...],
//   "hours":   [...]
// }

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/hive_provider.dart';
import '../../core/firebase/firebase_service.dart';

class ImportExportService {
  ImportExportService._();
  static final ImportExportService instance = ImportExportService._();

  static const _uuid = Uuid();

  // ── EXPORT JSON ───────────────────────────────────────────────────────────

  Future<void> exportJson() async {
    final aziende = HiveProvider.instance.aziende.values
        .map(_cast).toList();
    final hours = HiveProvider.instance.hours.values
        .map(_cast).toList();

    final payload = jsonEncode({
      'version':     3,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'aziende':     aziende,
      'hours':       hours,
    });

    final bytes    = Uint8List.fromList(utf8.encode(payload));
    final filename = 'timekeeper_backup_${_dateTag()}.json';
    final file     = XFile.fromData(bytes, name: filename, mimeType: 'application/json');

    await SharePlus.instance.share(
      ShareParams(files: [file], text: 'TimeKeeper Backup'),
    );
  }

  // ── IMPORT JSON ───────────────────────────────────────────────────────────

  /// Ritorna numero record importati, 0 se annullato, -1 se errore.
  Future<int> importJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return 0;

      final raw  = utf8.decode(result.files.single.bytes!);
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 1;
      final aziende = (data['aziende'] as List? ?? []).cast<Map<String, dynamic>>();
      final hours   = (data['hours']   as List? ?? []).cast<Map<String, dynamic>>();

      // v1/v2 usavano int id — normalizziamo a uuid
      if (version < 3) {
        return _importLegacyData(aziende: aziende, hours: hours);
      }

      return _importRawData(aziende: aziende, hours: hours);
    } catch (e) {
      debugPrint('[ImportExport] importJson: $e');
      return -1;
    }
  }

  // ── IMPORT SQLite .db (vecchia app Android) ───────────────────────────────

  Future<int> importSqliteDb() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return 0;

      final bytes = result.files.single.bytes!;

      final magic = utf8.decode(bytes.sublist(0, 15), allowMalformed: true);
      if (!magic.startsWith('SQLite format 3')) return -1;

      final aziende = _parseSqliteAziende(bytes);
      final hours   = _parseSqliteHours(bytes);

      if (aziende.isEmpty && hours.isEmpty) return -1;

      return _importLegacyData(aziende: aziende, hours: hours);
    } catch (e) {
      debugPrint('[ImportExport] importSqliteDb: $e');
      return -1;
    }
  }

  // ── SQLite binary parser ──────────────────────────────────────────────────

  List<Map<String, dynamic>> _parseSqliteAziende(Uint8List bytes) {
    final results = <Map<String, dynamic>>[];
    final str = _safeString(bytes);
    final jsonRe = RegExp(
      r'\{"enabled":(true|false),"start":"[\d:]+","end":"[\d:]+",'
      r'"activeDays":\[[\d,]+\],"lunchBreakMinutes":\d+'
      r'(?:,"automationStartDate":"[\d-]+")?}',
    );

    int fakeId = 1;
    for (final m in jsonRe.allMatches(str)) {
      try {
        final scheduleJson = m.group(0)!;
        final before       = str.substring((m.start - 200).clamp(0, m.start), m.start);
        final name         = _extractName(before);

        results.add({
          'id':              fakeId, // verrà rimappato in _importLegacyData
          'name':            name ?? 'Azienda $fakeId',
          'hourly_rate':     _extractRate(before, 1) ?? 0.0,
          'overtime_rate':   _extractRate(before, 2) ?? 0.0,
          'schedule_config': scheduleJson,
          'deleted':         0,
        });
        fakeId++;
      } catch (e) {
        debugPrint('[SQLite] azienda parse skip: $e');
      }
    }
    return results;
  }

  List<Map<String, dynamic>> _parseSqliteHours(Uint8List bytes) {
    final results = <Map<String, dynamic>>[];
    final str     = _safeString(bytes);

    final tsRe = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}');
    final allTs = tsRe.allMatches(str).map((m) => m.group(0)!).toList();

    int id = 1;
    for (var i = 0; i + 1 < allTs.length; i += 2) {
      try {
        final start = DateTime.parse(allTs[i]);
        final end   = DateTime.parse(allTs[i + 1]);
        if (!end.isAfter(start)) continue;
        if (end.difference(start).inHours > 24) continue;

        results.add({
          'id':          id++,
          'azienda_id':  1,
          'start_time':  allTs[i],
          'end_time':    allTs[i + 1],
          'lunch_break': 60,
          'notes':       null,
          'deleted':     0,
        });
      } catch (_) {}
    }
    return results;
  }

  // ── legacy import (v1/v2 con int id) ─────────────────────────────────────
  //
  // Converte int id → uuid e rimappa azienda_id → azienda_uuid.

  int _importLegacyData({
    required List<Map<String, dynamic>> aziende,
    required List<Map<String, dynamic>> hours,
  }) {
    int count = 0;
    final idMap = <int, String>{}; // vecchio int id → nuovo uuid

    final azBox = HiveProvider.instance.aziende;

    for (final a in aziende) {
      final oldId = (a['id'] as num?)?.toInt() ?? 0;

      // Controlla duplicati per nome
      final duplicate = azBox.values.cast<Map>().where(
        (m) => _cast(m)['name'] == a['name'],
      ).firstOrNull;

      if (duplicate != null) {
        final existingUuid = _cast(duplicate)['uuid'] as String? ?? _uuid.v4();
        idMap[oldId] = existingUuid;
        continue;
      }

      final newUuid = _uuid.v4();
      idMap[oldId]  = newUuid;

      azBox.put(newUuid, {
        ...a,
        'uuid':    newUuid,
        'deleted': a['deleted'] ?? 0,
      });
      count++;
    }

    final hBox = HiveProvider.instance.hours;
    for (final h in hours) {
      final oldAzId  = (h['azienda_id'] as num?)?.toInt() ?? 0;
      final azUuid   = idMap[oldAzId] ?? _uuid.v4();
      final newUuid  = _uuid.v4();

      hBox.put(newUuid, {
        ...h,
        'uuid':         newUuid,
        'azienda_uuid': azUuid,
        'deleted':      h['deleted'] ?? 0,
      });
      count++;
    }

    FirebaseService.instance.schedulePush();
    return count;
  }

  // ── v3 import (già con uuid) ──────────────────────────────────────────────

  int _importRawData({
    required List<Map<String, dynamic>> aziende,
    required List<Map<String, dynamic>> hours,
  }) {
    int count = 0;
    final azBox = HiveProvider.instance.aziende;
    final hBox  = HiveProvider.instance.hours;

    for (final a in aziende) {
      final uuid = a['uuid'] as String? ?? _uuid.v4();

      // Salta se già presente (stesso uuid)
      if (azBox.get(uuid) != null) continue;

      azBox.put(uuid, {...a, 'uuid': uuid});
      count++;
    }

    for (final h in hours) {
      final uuid = h['uuid'] as String? ?? _uuid.v4();

      if (hBox.get(uuid) != null) continue;

      hBox.put(uuid, {...h, 'uuid': uuid});
      count++;
    }

    FirebaseService.instance.schedulePush();
    return count;
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _safeString(Uint8List bytes) =>
      bytes.map((b) => (b >= 0x20 && b < 0x80) ? String.fromCharCode(b) : ' ').join();

  String? _extractName(String before) {
    final re = RegExp(r"([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9\s\-\.\']{1,49})\s*$");
    return re.firstMatch(before.trim())?.group(1)?.trim();
  }

  double? _extractRate(String context, int occurrence) {
    final re      = RegExp(r'\b(\d+(?:\.\d+)?)\b');
    final matches = re.allMatches(context).toList();
    if (matches.length < occurrence) return null;
    return double.tryParse(matches[matches.length - occurrence].group(1)!);
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));

  String _dateTag() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2,'0')}${n.day.toString().padLeft(2,'0')}';
  }
}