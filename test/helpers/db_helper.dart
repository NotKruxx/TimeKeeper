// test/helpers/db_helper.dart
//
// Setup Hive in-memory per i test.
// Firebase viene disabilitato — i repository chiamano schedulePush()
// che diventa no-op quando _disabled = true.

import 'package:hive_flutter/hive_flutter.dart';
import 'package:salvaore/core/database/hive_provider.dart';
import 'package:salvaore/core/firebase/firebase_service.dart';

class TestDb {
  static bool _registered = false;

  static Future<void> setup() async {
    // Disabilita Firebase — nessuna init richiesta nei test
    FirebaseService.instance.disableForTesting();

    if (!_registered) {
      Hive.init('test_db');
      _registered = true;
    }

    // Se i box sono già aperti, li riusiamo (evita lock conflict)
    if (!Hive.isBoxOpen('aziende')) await Hive.openBox<Map>('aziende');
    if (!Hive.isBoxOpen('hours'))   await Hive.openBox<Map>('hours');
    if (!Hive.isBoxOpen('auto_gen'))await Hive.openBox<String>('auto_gen');
    if (!Hive.isBoxOpen('meta'))    await Hive.openBox('meta');

    HiveProvider.instance.injectForTesting();
  }

  static Future<void> teardown() async {
    if (Hive.isBoxOpen('aziende')) await Hive.box<Map>('aziende').clear();
    if (Hive.isBoxOpen('hours'))   await Hive.box<Map>('hours').clear();
    if (Hive.isBoxOpen('auto_gen'))await Hive.box<String>('auto_gen').clear();
    if (Hive.isBoxOpen('meta'))    await Hive.box('meta').clear();
  }
}
