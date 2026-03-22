// lib/data/services/settings_service.dart
//
// Thin wrapper around SharedPreferences.
// Single init, cached instance — no await chain on every read.

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── rounding ──────────────────────────────────────────────────────────────
  bool get roundTimes => _prefs.getBool('round_times') ?? true;
  Future<void> setRoundTimes(bool v) => _prefs.setBool('round_times', v);

  // ── device identity ───────────────────────────────────────────────────────
  String? get deviceId => _prefs.getString('device_id');
  Future<void> setDeviceId(String id) => _prefs.setString('device_id', id);

  // ── last sync timestamp ───────────────────────────────────────────────────
  DateTime? get lastSync {
    final raw = _prefs.getString('last_sync');
    return raw != null ? DateTime.tryParse(raw) : null;
  }
  Future<void> setLastSync(DateTime t) =>
      _prefs.setString('last_sync', t.toIso8601String());
}
