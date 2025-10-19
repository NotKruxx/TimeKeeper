// lib/ui/pages/settings_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../../api/database_api.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isBackingUp = false;
  bool _isRestoring = false;

  Future<String> get _dbPath async {
    const dbName = 'work_hours_app.db';
    final dbFolder = await getDatabasesPath();
    return p.join(dbFolder, dbName);
  }

  Future<void> _backupDatabase() async {
    setState(() => _isBackingUp = true);
    try {
      await DatabaseApi.closeDatabase();

      final dbFile = File(await _dbPath);
      if (!await dbFile.exists()) {
        _showSnackBar('Database non trovato.', isError: true);
        return;
      }

      final outputPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Seleziona una cartella per il backup',
      );

      if (outputPath != null) {
        final backupFileName =
            'salvaore_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db';
        final backupFile = File(p.join(outputPath, backupFileName));
        await dbFile.copy(backupFile.path);
        _showSnackBar('Backup completato con successo!');
      }
    } catch (e) {
      _showSnackBar('Errore durante il backup: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Conferma Ripristino'),
        content: const Text(
          'Questa operazione sovrascriverà tutti i dati attuali e riavvierà l\'app. Procedere?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null) {
        final backupFile = File(result.files.single.path!);
        await DatabaseApi.closeDatabase();

        final dbPath = await _dbPath;
        await backupFile.copy(dbPath);

        _showSnackBar('Ripristino completato. Riavvio in corso...');
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) Phoenix.rebirth(context);
      }
    } catch (e) {
      _showSnackBar('Errore durante il ripristino: $e', isError: true);
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
          ListTile(
            leading: _isBackingUp
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup),
            title: const Text('Backup Dati'),
            subtitle: const Text('Esporta il database in un file sicuro.'),
            onTap: _isBackingUp || _isRestoring ? null : _backupDatabase,
          ),
          const Divider(),
          ListTile(
            leading: _isRestoring
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore),
            title: const Text('Ripristina Dati'),
            subtitle: const Text('Importa dati da un file di backup.'),
            onTap: _isBackingUp || _isRestoring ? null : _restoreDatabase,
          ),
        ],
      ),
    );
  }
}
