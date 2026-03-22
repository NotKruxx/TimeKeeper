// lib/ui/pages/settings_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/firebase/firebase_service.dart';
import '../../data/services/settings_service.dart';
import '../../ui/providers/dashboard_provider.dart';
import '../../ui/providers/companies_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isBusy    = false;
  bool _roundTimes = true;

  @override
  void initState() {
    super.initState();
    _roundTimes = SettingsService.instance.roundTimes;
  }

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

  Future<void> _signIn() async {
    await _setBusy(() async {
      final user = await FirebaseService.instance.signInWithGoogle();
      if (user != null && mounted) {
        await FirebaseService.instance.pullAll();
        if (!mounted) return;
        context.read<DashboardProvider>().load();
        context.read<CompaniesProvider>().load();
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
      context.read<DashboardProvider>().load();
      context.read<CompaniesProvider>().load();
    });
  }

  Future<void> _syncNow() async {
    await _setBusy(() async {
      await FirebaseService.instance.pullAll();
      if (!mounted) return;
      context.read<DashboardProvider>().load();
      context.read<CompaniesProvider>().load();
      _snack('Dati aggiornati!');
    });
  }

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
                backgroundImage: user?.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
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
              subtitle: const Text('I dati vengono sincronizzati automaticamente.'),
              trailing: _isBusy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                  : TextButton(
                      onPressed: _syncNow,
                      child: const Text('Aggiorna'),
                    ),
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
              subtitle: const Text(
                'Accedi con Google per sincronizzare i dati '
                'su tutti i tuoi dispositivi.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _signIn,
                icon: _isBusy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Accedi con Google'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.teal,
                ),
              ),
            ),
          ],
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
