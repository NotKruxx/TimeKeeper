// lib/main.dart
 
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
 
import 'core/database/hive_provider.dart';
import 'core/firebase/firebase_options.dart';  // generato da FlutterFire CLI
import 'core/firebase/firebase_service.dart';
import 'data/services/auto_shift_service.dart';
import 'data/services/settings_service.dart';
import 'ui/main_shell.dart';
import 'ui/providers/dashboard_provider.dart';
import 'ui/providers/companies_provider.dart';
 
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);
 
  // ── Firebase ──────────────────────────────────────────────────────────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
 
  // ── Hive (cache locale) ───────────────────────────────────────────────
  await HiveProvider.instance.init();
 
  // ── Settings ──────────────────────────────────────────────────────────
  await SettingsService.instance.init();
  if (SettingsService.instance.deviceId == null) {
    await SettingsService.instance.setDeviceId(const Uuid().v4());
  }
 
  // ── Se già loggato, scarica PRIMA i dati dal cloud ──────────────────
  // Importante: pullAll() deve venire prima di AutoShiftService.run()
  // così hasOverlap() vede i turni già esistenti e non li duplica.
  if (FirebaseService.instance.isSignedIn) {
    await FirebaseService.instance.pullAll().catchError(
      (e) => debugPrint('[Firebase] pullAll: $e'),
    );
  }
 
  // ── Auto-shift — gira DOPO il pull, idempotente ───────────────────────
  AutoShiftService.instance.run().catchError(
    (e) => debugPrint('[AutoShift] $e'),
  );
 
  runApp(Phoenix(child: const TimeKeeperApp()));
}
 
class TimeKeeperApp extends StatelessWidget {
  const TimeKeeperApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardProvider()..load()),
        ChangeNotifierProvider(create: (_) => CompaniesProvider()..load()),
      ],
      child: MaterialApp(
        title: 'TimeKeeper',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const MainShell(),
      ),
    );
  }
 
  ThemeData _buildTheme() => ThemeData.dark().copyWith(
    primaryColor: Colors.teal,
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: const ColorScheme.dark(
      primary: Colors.teal,
      secondary: Colors.tealAccent,
      surface: Color(0xFF1E1E1E),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1E1E1E),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Color(0xFF1E1E1E),
      centerTitle: true,
    ),
  );
}