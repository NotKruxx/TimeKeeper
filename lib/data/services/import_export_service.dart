// lib/data/services/import_export_service.dart
//
// Export → JSON
// Import → JSON (tutte le piattaforme) oppure .db SQLite vecchio (web: parsing binario)
//
// Struttura JSON:
// {
//   "version": 2,
//   "exported_at": "...",
//   "aziende": [...],
//   "hours":   [...]
// }

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/hive_provider.dart';
import '../../core/firebase/firebase_service.dart';

class ImportExportService {
  ImportExportService._();
  static final ImportExportService instance = ImportExportService._();

  // ── EXPORT JSON ───────────────────────────────────────────────────────────

  Future<void> exportJson() async {
    final aziende = HiveProvider.instance.aziende.values
        .map(_cast).toList();
    final hours = HiveProvider.instance.hours.values
        .map(_cast).toList();

    final payload = jsonEncode({
      'version':     2,
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

      final aziende = (data['aziende'] as List? ?? []).cast<Map<String, dynamic>>();
      final hours   = (data['hours']   as List? ?? []).cast<Map<String, dynamic>>();

      return _importRawData(aziende: aziende, hours: hours);
    } catch (e) {
      debugPrint('[ImportExport] importJson: $e');
      return -1;
    }
  }

  // ── IMPORT SQLite .db (vecchia app Android) ───────────────────────────────

  /// Legge il .db SQLite della vecchia app e lo importa.
  /// Funziona su web tramite parsing binario del formato SQLite.
  Future<int> importSqliteDb() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return 0;

      final bytes = result.files.single.bytes!;

      // Verifica magic SQLite
      final magic = utf8.decode(bytes.sublist(0, 15), allowMalformed: true);
      if (!magic.startsWith('SQLite format 3')) return -1;

      final aziende = _parseSqliteAziende(bytes);
      final hours   = _parseSqliteHours(bytes);

      if (aziende.isEmpty && hours.isEmpty) return -1;

      return _importRawData(aziende: aziende, hours: hours);
    } catch (e) {
      debugPrint('[ImportExport] importSqliteDb: $e');
      return -1;
    }
  }

  // ── SQLite binary parser ──────────────────────────────────────────────────
  //
  // Il formato SQLite memorizza i record come varints + typed serial values.
  // Per la vecchia app i campi chiave sono:
  //   azienda: id(int) name(text) hourly_rate(real) overtime_rate(real) schedule_config(text)
  //   hours_worked: id(int) azienda_id(int) start_time(text) end_time(text) lunch_break(int) notes(text)
  //
  // Strategia: cerchiamo i timestamp ISO nel binario (univoci e riconoscibili)
  // e ricostruiamo i record da lì. Per le aziende cerchiamo il JSON schedule_config.

  List<Map<String, dynamic>> _parseSqliteAziende(Uint8List bytes) {
    final results = <Map<String, dynamic>>[];
    // Cerca blocchi JSON schedule_config — sono univoci nel file
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
        final scheduleMap  = jsonDecode(scheduleJson) as Map<String, dynamic>;

        // Cerca il nome azienda nei ~200 byte prima del JSON
        final before = str.substring((m.start - 200).clamp(0, m.start), m.start);
        final name   = _extractName(before);

        // Cerca i rate nei byte dopo il nome (sono float64 BE in SQLite)
        // Approssimazione: usiamo 0 e lasciamo all'utente di correggere
        results.add({
          'id':              fakeId,
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

    // Timestamp pattern usato dalla vecchia app: "2025-12-09T08:00:00.000"
    final tsRe = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}');
    final allTs = tsRe.allMatches(str).map((m) => m.group(0)!).toList();

    // I timestamp vengono in coppie consecutive (start_time, end_time)
    int id = 1;
    for (var i = 0; i + 1 < allTs.length; i += 2) {
      try {
        final start = DateTime.parse(allTs[i]);
        final end   = DateTime.parse(allTs[i + 1]);
        if (!end.isAfter(start)) continue;
        if (end.difference(start).inHours > 24) continue;

        results.add({
          'id':          id++,
          'azienda_id':  1,   // verrà rimappato in _importRawData
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

  String _safeString(Uint8List bytes) =>
      bytes.map((b) => (b >= 0x20 && b < 0x80) ? String.fromCharCode(b) : ' ').join();

  String? _extractName(String before) {
    // Cerca l'ultima parola/frase di testo leggibile prima del JSON
    final re = RegExp(r"([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9\s\-\.\']{1,49})\s*$");
    return re.firstMatch(before.trim())?.group(1)?.trim();
  }

  double? _extractRate(String context, int occurrence) {
    // Cerca valori numerici tipo "8.5" o "10.0" nel contesto
    final re = RegExp(r'\b(\d+(?:\.\d+)?)\b');
    final matches = re.allMatches(context).toList();
    if (matches.length < occurrence) return null;
    return double.tryParse(matches[matches.length - occurrence].group(1)!);
  }

  // ── core import ───────────────────────────────────────────────────────────

  int _importRawData({
    required List<Map<String, dynamic>> aziende,
    required List<Map<String, dynamic>> hours,
  }) {
    int count = 0;
    final idMap = <int, int>{}; // vecchio id → nuovo id

    final azBox = HiveProvider.instance.aziende;

    for (final a in aziende) {
      final oldId = (a['id'] as num?)?.toInt() ?? 0;

      // Controlla duplicati per nome
      final duplicate = azBox.values.cast<Map>().where(
        (m) => _cast(m)['name'] == a['name'],
      ).firstOrNull;

      if (duplicate != null) {
        final existingId = (_cast(duplicate)['id'] as num?)?.toInt() ?? oldId;
        idMap[oldId] = existingId;
        continue;
      }

      final newId = HiveProvider.instance.nextAziendaId();
      idMap[oldId] = newId;
      azBox.put(newId, {
        ...a,
        'id':      newId,
        'deleted': a['deleted'] ?? 0,
      });
      count++;
    }

    final hBox = HiveProvider.instance.hours;
    for (final h in hours) {
      final oldAzId = (h['azienda_id'] as num?)?.toInt() ?? 0;
      final newAzId = idMap[oldAzId] ?? oldAzId;
      final newId   = HiveProvider.instance.nextHoursId();

      hBox.put(newId, {
        ...h,
        'id':         newId,
        'azienda_id': newAzId,
        'deleted':    h['deleted'] ?? 0,
      });
      count++;
    }

    FirebaseService.instance.schedulePush();
    return count;
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));

  String _dateTag() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2,'0')}${n.day.toString().padLeft(2,'0')}';
  }
}
