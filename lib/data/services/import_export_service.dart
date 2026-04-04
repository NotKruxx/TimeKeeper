// lib/data/services/import_export_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/azienda_model.dart';
import '../models/hours_worked_model.dart';

/// Un contenitore per i dati importati.
class ImportResult {
  final List<AziendaModel> aziende;
  final List<HoursWorkedModel> hours;
  
  ImportResult({required this.aziende, required this.hours});
}

class ImportExportService {
  ImportExportService._();
  static final ImportExportService instance = ImportExportService._();

  static const _uuid = Uuid();

  // ── EXPORT JSON ───────────────────────────────────────────────────────────

  /// Passa direttamente i dati correnti che hai in cache o nel provider.
  Future<void> exportJson({
    required List<AziendaModel> aziende,
    required List<HoursWorkedModel> hours,
  }) async {
    final payload = jsonEncode({
      'version':     3,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'aziende':     aziende.map((e) => e.toSqlite()).toList(),
      'hours':       hours.map((e) => e.toSqlite()).toList(),
    });

    final bytes    = Uint8List.fromList(utf8.encode(payload));
    final filename = 'timekeeper_backup_${_dateTag()}.json';
    final file     = XFile.fromData(bytes, name: filename, mimeType: 'application/json');

    await Share.shareXFiles([file], text: 'TimeKeeper Backup');
  }

  // ── IMPORT JSON ───────────────────────────────────────────────────────────

  /// Ritorna un [ImportResult] contenente i modelli parsati, oppure null se fallisce/annullato.
  Future<ImportResult?> importJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return null;

      final raw  = utf8.decode(result.files.single.bytes!);
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 1;
      final aziendeRaw = (data['aziende'] as List? ?? []).cast<Map<String, dynamic>>();
      final hoursRaw   = (data['hours']   as List? ?? []).cast<Map<String, dynamic>>();

      if (version < 3) {
        return _parseLegacyData(aziendeRaw, hoursRaw);
      }

      return _parseRawData(aziendeRaw, hoursRaw);
    } catch (e) {
      debugPrint('[ImportExport] importJson error: $e');
      return null;
    }
  }

  // ── IMPORT SQLite .db (vecchia app Android) ───────────────────────────────

  Future<void> importSqliteDb() async {
    debugPrint('Importazione diretta .db non supportata in questa versione.');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  ImportResult _parseRawData(
    List<Map<String, dynamic>> aziendeRaw,
    List<Map<String, dynamic>> hoursRaw,
  ) {
    final aziende = aziendeRaw.map((a) => AziendaModel.fromSqlite(a)).toList();
    final hours = hoursRaw.map((h) => HoursWorkedModel.fromSqlite(h)).toList();
    
    return ImportResult(aziende: aziende, hours: hours);
  }

  ImportResult _parseLegacyData(
    List<Map<String, dynamic>> aziendeRaw,
    List<Map<String, dynamic>> hoursRaw,
  ) {
    // Usiamo l'ID utente loggato su Supabase, o un fallback locale
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'local_user';
    final idMap = <int, String>{};
    
    final aziende = <AziendaModel>[];
    final hours = <HoursWorkedModel>[];

    for (final a in aziendeRaw) {
      final oldId = (a['id'] as num?)?.toInt() ?? 0;
      final newUuid = _uuid.v4();
      idMap[oldId] = newUuid;

      final model = AziendaModel(
        uuid: newUuid,
        userId: uid,
        name: a['name'] as String? ?? 'Azienda',
        hourlyRate: (a['hourly_rate'] as num?)?.toDouble() ?? 0.0,
        overtimeRate: (a['overtime_rate'] as num?)?.toDouble() ?? 0.0,
        scheduleConfig: a['schedule_config'] is String 
            ? jsonDecode(a['schedule_config'] as String) : (a['schedule_config'] ?? {}),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        isSynced: false,
        syncAction: 'insert',
      );
      aziende.add(model);
    }

    for (final h in hoursRaw) {
      final oldAzId = (h['azienda_id'] as num?)?.toInt() ?? 0;
      final azUuid = idMap[oldAzId];
      if (azUuid == null) continue;

      final model = HoursWorkedModel.create(
        userId: uid,
        aziendaUuid: azUuid,
        startTime: DateTime.parse(h['start_time'] as String),
        endTime: DateTime.parse(h['end_time'] as String),
        lunchBreak: (h['lunch_break'] as num?)?.toInt() ?? 60,
        notes: h['notes'] as String?,
      );
      hours.add(model);
    }

    return ImportResult(aziende: aziende, hours: hours);
  }

  String _dateTag() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
}