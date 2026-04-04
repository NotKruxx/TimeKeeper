// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/service/supabase_service.dart';
import 'core/service/offline_write_queue.dart';

// 1. IMPORT AGGIUNTO QUI
import 'data/services/settings_service.dart'; 

import 'ui/main_shell.dart';
import 'ui/pages/login_page.dart';
import 'ui/providers/dashboard_provider.dart';
import 'ui/providers/companies_provider.dart';
import 'ui/providers/data_cache_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);

  // ── Supabase ───────────────────────────────────────────────────────────────
  await Supabase.initialize(
    url: 'https://tjioanppdzovyepjltug.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqaW9hbnBwZHpvdnllcGpsdHVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyNDA4NzAsImV4cCI6MjA5MDgxNjg3MH0.LxwKLTch1YDBE-59JgdNT0L6E-YdHH7mCn6AgRmktBo',
  );

  // 2. INIZIALIZZAZIONE SETTINGS SERVICE AGGIUNTA QUI
  // Questo risolve l'errore LateInitializationError su SharedPreferences
  await SettingsService.instance.init();

  // ── Offline Queue ─────────────────────────────────────────────────────────
  await OfflineWriteQueue.instance.init();

  runApp(Phoenix(child: const TimeKeeperApp()));
}

class TimeKeeperApp extends StatelessWidget {
  const TimeKeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DataCacheProvider()),
        ChangeNotifierProxyProvider<DataCacheProvider, DashboardProvider>(
          create: (_) => DashboardProvider(),
          update: (_, cache, dash) => dash!..updateFromCache(cache),
        ),
        ChangeNotifierProxyProvider<DataCacheProvider, CompaniesProvider>(
          create: (_) => CompaniesProvider(),
          update: (_, cache, comp) => comp!..updateFromCache(cache),
        ),
      ],
      child: MaterialApp(
        title: 'TimeKeeper',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.teal,
          colorScheme: const ColorScheme.dark(
            primary: Colors.teal,
            secondary: Colors.tealAccent,
          ),
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        final session = snapshot.data?.session;
        if (session != null) {
          return const MainShell();
        }
        
        return const LoginPage();
      },
    );
  }
}