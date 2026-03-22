// test/helpers/db_helper.dart
//
// Soluzione Windows-safe al lock Hive:
// - Ogni processo usa una directory univoca basata su timestamp + random
// - I box non vengono mai chiusi né la directory cancellata durante i test
// - Tra un test e l'altro si fa solo clear() dei box (operazione sicura)
// - dispose() è un no-op — la directory viene lasciata e ignorata

import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:salvaore/core/database/hive_provider.dart';
import 'package:salvaore/core/firebase/firebase_service.dart';

class TestDb {
  static bool _initialized = false;

  static Future<void> setup() async {
    FirebaseService.instance.disableForTesting();

    if (!_initialized) {
      // Directory unica per questo processo — mai condivisa
      final rnd = Random().nextInt(999999999);
      final ts  = DateTime.now().microsecondsSinceEpoch;
      Hive.init('test_db_${ts}_$rnd');

      await Hive.openBox<Map>('aziende');
      await Hive.openBox<Map>('hours');
      await Hive.openBox<String>('auto_gen');
      await Hive.openBox('meta');
      _initialized = true;
    }

    HiveProvider.instance.injectForTesting();
    await _clearAll();
  }

  static Future<void> teardown() async {
    await _clearAll();
  }

  // No-op — i box rimangono aperti per tutto il processo di test
  static Future<void> dispose() async {}

  static Future<void> _clearAll() async {
    if (!_initialized) return;
    await Future.wait([
      Hive.box<Map>('aziende').clear(),
      Hive.box<Map>('hours').clear(),
      Hive.box<String>('auto_gen').clear(),
      Hive.box('meta').clear(),
    ]);
  }
}