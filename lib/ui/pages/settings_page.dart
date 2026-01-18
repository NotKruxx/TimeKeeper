// lib/ui/pages/settings_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
// import 'package:qr_flutter/qr_flutter.dart'; // RIMOSSO TEMPORANEAMENTE
import '../../api/database_api.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isBackingUp = false;
  bool _isRestoring = false;
  // final TextEditingController _qrController = TextEditingController(); // RIMOSSO TEMPORANEAMENTE
  bool _arrotondaOrari = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _arrotondaOrari = prefs.getBool('arrotonda_orari') ?? true;
      });
    }
  }

  Future<void> _setArrotondaOrari(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('arrotonda_orari', value);
    if (mounted) {
      setState(() {
        _arrotondaOrari = value;
      });
    }
  }

  Future<String> get _dbPath async {
    const dbName = 'work_hours_app.db';
    final dbFolder = await getDatabasesPath();
    return p.join(dbFolder, dbName);
  }

  /* RIMOSSO TEMPORANEAMENTE
  Future<void> _editQrCode() async {
    final prefs = await SharedPreferences.getInstance();
    String currentCode =
        prefs.getString('custom_qr_code') ??
        "IL_MIO_CODICE_SPECIALE_PER_TIMBRARE";
    _qrController.text = currentCode;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Configura QR Code"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Inserisci il testo del QR Code per timbrare."),
            const SizedBox(height: 10),
            TextField(
              controller: _qrController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Codice Segreto',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annulla"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_qrController.text.isNotEmpty) {
                await prefs.setString(
                  'custom_qr_code',
                  _qrController.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(context);
                  _showSnackBar("Codice salvato!");
                }
              }
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  Future<void> _showQrDisplay() async {
    final prefs = await SharedPreferences.getInstance();
    final code =
        prefs.getString('custom_qr_code') ??
        "IL_MIO_CODICE_SPECIALE_PER_TIMBRARE";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Il tuo QR Code"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                code,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Chiudi"),
          ),
        ],
      ),
    );
  }
  */

  Future<void> _backupDatabase() async {
    setState(() => _isBackingUp = true);
    try {
      await DatabaseApi.closeDatabase();
      final dbPath = await _dbPath;
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        _showSnackBar('Database non trovato.', isError: true);
        return;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        final xFile = XFile(dbFile.path, name: 'salvaore_backup.db');
        await Share.shareXFiles([xFile], text: 'Backup Database Salvaore');
      } else {
        String? outputDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Seleziona cartella di backup',
        );

        if (outputDirectory != null) {
          final fileName =
              'salvaore_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db';
          final destination = p.join(outputDirectory, fileName);
          await dbFile.copy(destination);
          _showSnackBar('Backup salvato in: $destination');
        }
      }
    } catch (e) {
      _showSnackBar('Errore backup: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma Ripristino'),
        content: const Text(
          'I dati attuali verranno sovrascritti. Continuare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sì, Ripristina',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);
    try {
      final result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        final backupFile = File(result.files.single.path!);

        if (await backupFile.length() == 0) {
          throw Exception("File vuoto.");
        }

        await DatabaseApi.closeDatabase();
        final targetPath = await _dbPath;

        await backupFile.copy(targetPath);

        _showSnackBar('Ripristino completato! Riavvio...');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Phoenix.rebirth(context);
      }
    } catch (e) {
      _showSnackBar('Errore ripristino: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          SwitchListTile(
            title: const Text('Arrotonda orari in automatico'),
            subtitle: const Text('Arrotonda inizio e fine alla mezz\'ora più vicina.'),
            value: _arrotondaOrari,
            onChanged: _setArrotondaOrari,
          ),
          const Divider(),
          /* RIMOSSO TEMPORANEAMENTE
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('Configura QR Code'),
            subtitle: const Text('Modifica il codice o mostralo.'),
            onTap: _editQrCode,
            trailing: IconButton(
              icon: const Icon(Icons.visibility),
              onPressed: _showQrDisplay,
              tooltip: "Mostra QR Code",
            ),
          ),
          const Divider(),
          */
          ListTile(
            leading: _isBackingUp
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.save),
            title: const Text('Esporta Database'),
            subtitle: Text(
              Platform.isAndroid || Platform.isIOS
                  ? 'Condividi file'
                  : 'Salva in una cartella',
            ),
            onTap: _isBackingUp || _isRestoring ? null : _backupDatabase,
          ),
          const Divider(),
          ListTile(
            leading: _isRestoring
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.folder_open),
            title: const Text('Importa Database'),
            subtitle: const Text('Ripristina da file .db'),
            onTap: _isBackingUp || _isRestoring ? null : _restoreDatabase,
          ),
        ],
      ),
    );
  }
}