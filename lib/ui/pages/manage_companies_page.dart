// lib/ui/pages/manage_companies_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/azienda_model.dart';
import '../providers/data_cache_provider.dart';
import '../providers/companies_provider.dart';
import 'azienda_form_page.dart'; // IMPORTIAMO LA NUOVA PAGINA

class ManageCompaniesPage extends StatefulWidget {
  const ManageCompaniesPage({super.key});

  @override
  State<ManageCompaniesPage> createState() => _ManageCompaniesPageState();
}

class _ManageCompaniesPageState extends State<ManageCompaniesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataCacheProvider>().refresh();
    });
  }

  // ── INVECE DI APRIRE IL DIALOGO, APRIAMO LA PAGINA COMPLETA ──
  void _goToAziendaForm([AziendaModel? azienda]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AziendaFormPage(aziendaToEdit: azienda),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CompaniesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestisci Aziende'),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.aziende.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.business, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Nessuna azienda aggiunta.'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _goToAziendaForm(),
                        child: const Text('Aggiungi Azienda'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.aziende.length,
                  itemBuilder: (context, index) {
                    final az = provider.aziende[index];
                    return Card(
                      child: ListTile(
                        title: Text(az.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Paga oraria: ${az.hourlyRate.toStringAsFixed(2)} €'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.orange),
                              onPressed: () => _goToAziendaForm(az), // <-- MODIFICA
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDelete(az),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: provider.aziende.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _goToAziendaForm(), // <-- AGGIUNGI
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _confirmDelete(AziendaModel az) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Azienda'),
        content: Text('Sei sicuro di voler eliminare "${az.name}"? Verranno eliminate anche tutte le ore associate.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<DataCacheProvider>().deleteAzienda(az.uuid);
    }
  }
}