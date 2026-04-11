// lib/ui/providers/data_cache_provider.dart

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/service/offline_write_queue.dart';
import '../../data/models/azienda_model.dart';
import '../../data/models/hours_worked_model.dart';

class DataCacheProvider extends ChangeNotifier {
  DataCacheProvider() {
    _init();
  }

  List<AziendaModel> _aziende = [];
  List<HoursWorkedModel> _hours = [];
  List<Map<String, dynamic>> _deletedShifts = [];
  
  bool _isLoading = false;

  List<AziendaModel> get aziende => _aziende;
  List<HoursWorkedModel> get hours => _hours;
  bool get isLoading => _isLoading;

  Future<void> _init() async {
    await refresh();
    await _generateAutomaticShifts();

    Connectivity().onConnectivityChanged.listen((result) {
      final isConnected = result is List 
          ? (result as List).any((r) => r != ConnectivityResult.none)
          : result != ConnectivityResult.none;

      if (isConnected) {
        OfflineWriteQueue.instance.processQueue().then((_) => refresh());
      }
    });
  }

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      
      if (uid == null) {
        _aziende.clear();
        _hours.clear();
        _deletedShifts.clear();
        _isLoading = false;
        notifyListeners();
        return; 
      }

      // MODIFICA: Rimosso il filtro ".isFilter('deleted_at', null)" perché ora usiamo Hard Delete
      final results = await Future.wait([
        client.from('aziende').select().eq('user_id', uid),
        client.from('hours_worked').select().eq('user_id', uid),
        client.from('deleted_shifts').select('day_key, azienda_uuid').eq('user_id', uid),
      ]);

      _aziende = (results[0] as List).map((e) => AziendaModel.fromSupabase(e as Map<String, dynamic>)).toList();
      _hours = (results[1] as List).map((e) => HoursWorkedModel.fromSupabase(e as Map<String, dynamic>)).toList();
      _deletedShifts = (results[2] as List).map((e) => e as Map<String, dynamic>).toList();
      
    } catch (e) {
      debugPrint('[DataCacheProvider] Refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Motore di Generazione Automatica Turni ──────────────────────────────
  Future<void> _generateAutomaticShifts() async {
    final now = DateTime.now();
    bool addedNewShifts = false;

    for (final az in _aziende) {
      if (az.scheduleConfig['auto_generate'] == true) {
        
        final sinceStr = az.scheduleConfig['auto_generate_since'] as String?;
        if (sinceStr == null) continue;

        final workDays = (az.scheduleConfig['work_days'] as List?)?.cast<int>() ?? [];
        final startTimeStr = az.scheduleConfig['start_time'] as String?;
        final endTimeStr = az.scheduleConfig['end_time'] as String?;
        final lunchBreak = az.scheduleConfig['lunch_break'] as int? ?? 60;

        if (workDays.isEmpty || startTimeStr == null || endTimeStr == null) continue;

        DateTime startDate = DateTime.parse(sinceStr).toLocal();
        DateTime currentDay = DateTime(startDate.year, startDate.month, startDate.day);
        final endDay = DateTime(now.year, now.month, now.day);

        while (currentDay.isBefore(endDay) || currentDay.isAtSameMomentAs(endDay)) {
          if (workDays.contains(currentDay.weekday)) {
            
            final dayKey = DateFormat('yyyy-MM-dd').format(currentDay);
            final isBlacklisted = _deletedShifts.any(
              (d) => d['day_key'] == dayKey && d['azienda_uuid'] == az.uuid
            );

            if (isBlacklisted) {
              currentDay = currentDay.add(const Duration(days: 1));
              continue;
            }
            
            final exists = _hours.any((h) {
              final hLocal = h.startTime.toLocal();
              return h.aziendaUuid == az.uuid &&
                     hLocal.year == currentDay.year &&
                     hLocal.month == currentDay.month &&
                     hLocal.day == currentDay.day;
            });

            if (!exists) {
              final sParts = startTimeStr.split(':');
              final eParts = endTimeStr.split(':');
              DateTime sTime = DateTime(currentDay.year, currentDay.month, currentDay.day, int.parse(sParts[0]), int.parse(sParts[1]));
              DateTime eTime = DateTime(currentDay.year, currentDay.month, currentDay.day, int.parse(eParts[0]), int.parse(eParts[1]));
              if (eTime.isBefore(sTime)) eTime = eTime.add(const Duration(days: 1)); 
              
              if (sTime.isBefore(now)) {
                final newShift = HoursWorkedModel.create(
                  userId: az.userId,
                  aziendaUuid: az.uuid,
                  startTime: sTime,
                  endTime: eTime,
                  lunchBreak: lunchBreak,
                  notes: 'Turno generato automaticamente',
                );
                
                try {
                  await Supabase.instance.client.from('hours_worked').upsert(
                    newShift.toSupabase(),
                    onConflict: 'uuid',
                  );
                  
                  _hours.add(newShift);
                  addedNewShifts = true;
                } on PostgrestException catch (e) {
                  if (e.code == '23505') {
                    print('ℹ️ Turno automatico già esistente, ignorato. ($dayKey)');
                  } else {
                    await OfflineWriteQueue.instance.enqueue(
                      table: 'hours_worked', action: 'insert', data: newShift.toSupabase()
                    );
                  }
                } catch (e) {
                  await OfflineWriteQueue.instance.enqueue(
                      table: 'hours_worked', action: 'insert', data: newShift.toSupabase()
                  );
                }
              }
            }
          }
          currentDay = currentDay.add(const Duration(days: 1));
        }
      }
    }

    if (addedNewShifts) {
      notifyListeners();
    }
  }

  // ─── Azienda Mutations ───────────────────────────────────────────────────
  Future<void> saveAzienda(AziendaModel model) async {
    final index = _aziende.indexWhere((e) => e.uuid == model.uuid);
    if (index >= 0) {
      _aziende[index] = model;
    } else {
      _aziende.add(model);
    }
    notifyListeners();

    try {
      await Supabase.instance.client.from('aziende').upsert(model.toSupabase());
    } catch (e) {
      await OfflineWriteQueue.instance.enqueue(
        table: 'aziende',
        action: 'insert', 
        data: model.toSupabase(),
      );
    }
  }

  // ─── Hours Mutations ─────────────────────────────────────────────────────
  Future<void> saveHour(HoursWorkedModel model) async {
    final index = _hours.indexWhere((e) => e.uuid == model.uuid);
    if (index >= 0) {
      _hours[index] = model;
    } else {
      _hours.add(model);
    }
    notifyListeners();

    try {
      await Supabase.instance.client.from('hours_worked').upsert(
        model.toSupabase(),
        onConflict: 'uuid',
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        print('ℹ️ Rilevato tentativo di salvataggio duplicato per le ore, ignorato. (${model.uuid})');
      } else {
        await OfflineWriteQueue.instance.enqueue(
          table: 'hours_worked',
          action: 'insert',
          data: model.toSupabase(),
        );
      }
    } catch (e) {
      await OfflineWriteQueue.instance.enqueue(
        table: 'hours_worked',
        action: 'insert',
        data: model.toSupabase(),
      );
    }
  }

  // ─── Delete Mutations (MODIFICATE PER HARD DELETE) ────────────────────────
  Future<void> deleteAzienda(String uuid) async {
    _aziende.removeWhere((e) => e.uuid == uuid);
    notifyListeners();

    try {
      await Supabase.instance.client
          .from('aziende')
          .delete()
          .eq('uuid', uuid);
    } catch (e) {
      await OfflineWriteQueue.instance.enqueue(
        table: 'aziende',
        action: 'delete',
        data: {'uuid': uuid},
      );
    }
  }

  Future<void> deleteHour(String uuid) async {
    _hours.removeWhere((e) => e.uuid == uuid);
    notifyListeners();

    try {
      await Supabase.instance.client
          .from('hours_worked')
          .delete()
          .eq('uuid', uuid);
    } catch (e) {
      await OfflineWriteQueue.instance.enqueue(
        table: 'hours_worked',
        action: 'delete',
        data: {'uuid': uuid},
      );
    }
  }
}