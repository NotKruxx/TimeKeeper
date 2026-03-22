// lib/ui/pages/settings_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/firebase/firebase_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/import_export_service.dart';
import '../../ui/providers/dashboard_provider.dart';
import '../../ui/providers/companies_provider.dart';

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
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _setBusy(Future<void> Function() fn) async {
    setState(() => _isBusy = true);
    try { await fn(); }
    catch (e) { _snack('Errore: $e', isError: true); }
    finally { if (mounted) setState(() => _isBusy = false); }
  }

  void _reload() {
    context.read<DashboardProvider>().load();
    context.read<CompaniesProvider>().load();
  }

  // ── auth ──────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    await _setBusy(() async {
      final user = await FirebaseService.instance.signInWithGoogle();
      if (user != null && mounted) {
        await FirebaseService.instance.pullAll();
        if (!mounted) return;
        _reload();
        _snack('Benvenuto, ${user.displayName ?? user.email}!');
      } else {
        _snack('Accesso annullato.', isError: true);
      }
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma logout'),
        content: const Text(
          'I dati locali verranno rimossi da questo dispositivo. '
          'Sono al sicuro su Firebase e torneranno al prossimo login.',
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
      await FirebaseService.instance.signOut();
      if (!mounted) return;
      _reload();
    });
  }

  Future<void> _syncNow() async {
    await _setBusy(() async {
      await FirebaseService.instance.pullAll();
      if (!mounted) return;
      _reload();
      _snack('Dati aggiornati!');
    });
  }

  // ── import / export ───────────────────────────────────────────────────────

  Future<void> _exportJson() async {
    await _setBusy(() async {
      await ImportExportService.instance.exportJson();
    });
  }

  Future<void> _importJson() async {
    await _setBusy(() async {
      final count = await ImportExportService.instance.importJson();
      if (!mounted) return;
      if (count == 0) {
        _snack('Importazione annullata.');
      } else if (count < 0) {
        _snack('File non valido o corrotto.', isError: true);
      } else {
        _reload();
        _snack('$count record importati con successo!');
      }
    });
  }

  Future<void> _importSqliteDb() async {
    // Mostra avviso prima dell'import
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa dal vecchio DB'),
        content: const Text(
          'Seleziona il file work_hours_app.db dalla vecchia app Android.\n\n'
          'I dati verranno aggiunti a quelli esistenti senza sovrascrivere. '
          'Le aziende con lo stesso nome vengono ignorate.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continua')),
        ],
      ),
    );
    if (confirmed != true) return;

    await _setBusy(() async {
      final count = await ImportExportService.instance.importSqliteDb();
      if (!mounted) return;
      if (count == 0) {
        _snack('Importazione annullata.');
      } else if (count < 0) {
        _snack('File non riconosciuto. Assicurati di selezionare il file .db della vecchia app.', isError: true);
      } else {
        _reload();
        _snack('$count record importati dal vecchio database!');
      }
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fb       = FirebaseService.instance;
    final signedIn = fb.isSignedIn;
    final user     = fb.currentUser;

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
                backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null
                    ? Text(user?.displayName?.substring(0, 1).toUpperCase() ?? '?')
                    : null,
              ),
              title: Text(user?.displayName ?? 'Utente'),
              subtitle: Text(user?.email ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_done, color: Colors.tealAccent),
              title: const Text('Sincronizzazione attiva'),
              subtitle: const Text('I dati vengono sincronizzati automaticamente su Firebase.'),
              trailing: _isBusy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                  : TextButton(onPressed: _syncNow, child: const Text('Aggiorna')),
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
              subtitle: const Text('Accedi con Google per sincronizzare i dati su tutti i dispositivi.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _signIn,
                icon: _isBusy
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Accedi con Google'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.teal,
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
            subtitle: const Text('Scarica un backup completo di aziende e ore.'),
            trailing: _isBusy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _exportJson,
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline, color: Colors.orange),
            title: const Text('Importa dati (JSON)'),
            subtitle: const Text('Ripristina da un backup JSON precedentemente esportato.'),
            trailing: _isBusy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _importJson,
          ),
          ListTile(
            leading: const Icon(Icons.storage, color: Colors.grey),
            title: const Text('Importa dalla vecchia app'),
            subtitle: const Text('Importa il file .db SQLite dalla versione Android precedente.'),
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
