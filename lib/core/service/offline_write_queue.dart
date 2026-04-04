// lib/core/service/offline_write_queue.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class OfflineWriteQueue {
  OfflineWriteQueue._();
  static final OfflineWriteQueue instance = OfflineWriteQueue._();

  static const String _queueKey = 'offline_mutation_queue';

  // Mantenuto per compatibilità con main.dart
  Future<void> init() async {} 

  Future<void> enqueue({
    required String table,
    required String action,
    required Map<String, dynamic> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    final mutation = {
      'id': const Uuid().v4(),
      'table': table,
      'action': action,
      'payload': data, 
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    queue.add(jsonEncode(mutation));
    await prefs.setStringList(_queueKey, queue);
  }

  Future<void> processQueue() async {
    final session = Supabase.instance.client.auth.currentSession;
    // Se l'utente non è loggato o la sessione è scaduta, non fare nulla
    if (session == null || session.isExpired) return;

    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];
    if (queue.isEmpty) return;

    final client = Supabase.instance.client;
    final remainingQueue = <String>[];

    // Proviamo a processare ogni elemento della coda
    for (final item in queue) {
      try {
        final mutation = jsonDecode(item) as Map<String, dynamic>;
        final table = mutation['table'] as String;
        final action = mutation['action'] as String;
        final data = mutation['payload'] as Map<String, dynamic>;

        if (action == 'delete') {
          await client.from(table).delete().eq('uuid', data['uuid']);
        } else {
          await client.from(table).upsert(data);
        }
        
        // Se ha successo, NON lo aggiungiamo a remainingQueue. Verrà rimosso.
      } catch (e) {
        print('[OfflineWriteQueue] Errore elaborazione (forse offline): $e');
        // Se fallisce, lo rimettiamo nella coda rimanente per riprovare al prossimo avvio
        remainingQueue.add(item);
      }
    }

    // Salviamo la coda aggiornata
    await prefs.setStringList(_queueKey, remainingQueue);
  }
}