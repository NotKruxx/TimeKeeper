// lib/ui/pages/settings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Import per gestire l'errore dell'avatar

import '../../core/service/supabase_service.dart';
import '../../core/service/offline_write_queue.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/import_export_service.dart';
import '../../ui/providers/data_cache_provider.dart';
import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isBusy      = false;
  bool _roundTimes  = true;

  @override
  void initState() {
    super.initState();
    _roundTimes = SettingsService.instance.roundTimes;
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Theme.of(context).snackBarTheme.backgroundColor,
    ));
  }

  Future<void> _setBusy(Future<void> Function() fn) async {
    setState(() => _isBusy = true);
    try { await fn(); }
    catch (e) { _snack(e.toString().replaceAll('Exception: ', ''), isError: true); }
    finally { if (mounted) setState(() => _isBusy = false); }
  }

  // ── auth ──────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()));
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma logout'),
        content: const Text(
          'I dati in sospeso verranno persi se non sincronizzati. '
          'Sei sicuro di voler uscire?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Esci', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _setBusy(() async {
      await SupabaseService.instance.signOut();
      if (!mounted) return;
      // Svuota la cache locale, sarà ricaricata al prossimo login
      await context.read<DataCacheProvider>().refresh();
    });
  }

  Future<void> _syncNow() async {
    await _setBusy(() async {
      await OfflineWriteQueue.instance.processQueue();
      // Dopo aver processato la coda, facciamo un refresh per essere sicuri
      // di avere lo stato più aggiornato dal server.
      if (mounted) {
        await context.read<DataCacheProvider>().refresh();
      }
      _snack('Sincronizzazione completata!');
    });
  }

  // ── import / export ───────────────────────────────────────────────────────

  Future<void> _exportJson() async {
    await _setBusy(() async {
      final cache = context.read<DataCacheProvider>();
      await ImportExportService.instance.exportJson(
        aziende: cache.aziende,
        hours: cache.hours,
      );
      _snack('Esportazione completata!');
    });
  }

  Future<void> _importJson() async {
    await _setBusy(() async {
      final result = await ImportExportService.instance.importJson();
      if (!mounted) return;
      
      if (result == null) {
        // L'errore viene già gestito nel _setBusy, qui non facciamo nulla.
        return;
      }

      final cache = context.read<DataCacheProvider>();
      int count = 0;

      for (final a in result.aziende) {
        await cache.saveAzienda(a);
        count++;
      }
      for (final h in result.hours) {
        await cache.saveHour(h);
        count++;
      }

      // Dopo un'importazione massiva, è giusto fare un refresh per allineare tutto
      await cache.refresh();

      _snack('$count record importati con successo!');
    });
  }

  Future<void> _importSqliteDb() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa dalla vecchia app'),
        content: const Text(
          'Questa funzione non è più supportata. Usa la funzione di esportazione JSON dalla vecchia app per creare un file di backup compatibile.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ho capito')),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sb       = SupabaseService.instance;
    final signedIn = sb.isSignedIn;
    final user     = sb.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Preferenze ────────────────────────────────────────────────────
          _SectionHeader('Preferenze'),
          SwitchListTile(
            title: const Text('Arrotonda orari'),
            subtitle: const Text("Arrotonda inizio e fine alla mezz'ora più vicina."),
            value: _roundTimes,
            onChanged: (v) async {
              await SettingsService.instance.setRoundTimes(v);
              setState(() => _roundTimes = v);
            },
          ),
          const Divider(),

          // ── Account ───────────────────────────────────────────────────────
          _SectionHeader('Account e Sincronizzazione'),
          if (signedIn) ...[
            ListTile(
              leading: CircleAvatar(
                backgroundImage: user?.userMetadata?['avatar_url'] != null 
                    ? NetworkImage(user!.userMetadata!['avatar_url'] as String) 
                    : null,
                onBackgroundImageError: (_, __) {
                  // Gestisce l'errore 429 (Too Many Requests) o altri problemi di rete
                  debugPrint("Impossibile caricare l'avatar di Google.");
                },
                child: user?.userMetadata?['avatar_url'] == null
                    ? Text((user?.userMetadata?['full_name'] as String?)?.substring(0, 1).toUpperCase() 
                        ?? user?.email?.substring(0, 1).toUpperCase() ?? '?')
                    : null,
              ),
              title: Text(user?.userMetadata?['full_name'] as String? ?? 'Utente'),
              subtitle: Text(user?.email ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_done, color: Colors.tealAccent),
              title: const Text('Sincronizzazione attiva'),
              subtitle: const Text('I dati vengono sincronizzati automaticamente.'),
              trailing: _isBusy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                  : TextButton(onPressed: _syncNow, child: const Text('Forza Aggiorna')),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Esci'),
              onTap: _isBusy ? null : _signOut,
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.cloud_off, color: Colors.grey),
              title: const Text('Non connesso'),
              subtitle: const Text('Accedi per sincronizzare i dati su tutti i dispositivi.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _signIn,
                icon: _isBusy
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Accedi'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
          const Divider(),

          // ── Backup / Ripristino ───────────────────────────────────────────
          _SectionHeader('Backup e Ripristino'),
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.tealAccent),
            title: const Text('Esporta dati (JSON)'),
            subtitle: const Text('Crea un backup completo di aziende e ore.'),
            trailing: _isBusy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _exportJson,
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline, color: Colors.orange),
            title: const Text('Importa dati (JSON)'),
            subtitle: const Text('Ripristina da un file di backup.'),
            trailing: _isBusy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _importJson,
          ),
          ListTile(
            leading: const Icon(Icons.storage, color: Colors.grey),
            title: const Text('Importa dalla vecchia app'),
            subtitle: const Text('Funzione non più disponibile.'),
            trailing: _isBusy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _importSqliteDb,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.2,
      ),
    ),
  );
}