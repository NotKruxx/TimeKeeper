// lib/ui/pages/manage_companies_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api/database_api.dart';
import '../../models/azienda.dart';

class ManageCompaniesPage extends StatefulWidget {
  const ManageCompaniesPage({super.key});
  @override
  State<ManageCompaniesPage> createState() => _ManageCompaniesPageState();
}

class _ManageCompaniesPageState extends State<ManageCompaniesPage> {
  final DatabaseApi _dbApi = DatabaseApi();
  late Future<List<Azienda>> _aziendeFuture;

  @override
  void initState() {
    super.initState();
    _refreshAziende();
  }

  void _refreshAziende() {
    setState(() {
      _aziendeFuture = _dbApi.getAziende();
    });
  }

  Future<void> _showAddCompanyDialog({Azienda? azienda}) async {
    final nameController = TextEditingController(text: azienda?.name);
    final rateController = TextEditingController(
      text: azienda?.hourlyRate.toStringAsFixed(2) ?? '0.00',
    );
    final overtimeController = TextEditingController(
      text: azienda?.overtimeRate.toStringAsFixed(2) ?? '0.00',
    );
    final isEditing = azienda != null;

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Modifica Azienda' : 'Aggiungi Azienda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome azienda'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: rateController,
                  decoration: const InputDecoration(
                    labelText: 'Paga Oraria (€)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: overtimeController,
                  decoration: const InputDecoration(
                    labelText: 'Paga Straordinario (€)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final hourlyRate = double.tryParse(rateController.text) ?? 0.0;
                final overtimeRate =
                    double.tryParse(overtimeController.text) ?? hourlyRate;
                if (name.isNotEmpty) {
                  final newAzienda = Azienda(
                    id: azienda?.id,
                    name: name,
                    hourlyRate: hourlyRate,
                    overtimeRate: overtimeRate,
                  );
                  if (isEditing) {
                    await _dbApi.updateAzienda(newAzienda);
                  } else {
                    await _dbApi.addAzienda(newAzienda);
                  }
                  Navigator.pop(context);
                  _refreshAziende();
                }
              },
              child: const Text('Salva'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCompany(int id) async {
    await _dbApi.deleteAzienda(id);
    _refreshAziende();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestisci Aziende')),
      body: FutureBuilder<List<Azienda>>(
        future: _aziendeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(child: Text('Errore: ${snapshot.error}'));
          final aziende = snapshot.data ?? [];
          if (aziende.isEmpty)
            return const Center(
              child: Text(
                'Nessuna azienda trovata. Tocca + per aggiungerne una.',
              ),
            );
          return ListView.builder(
            itemCount: aziende.length,
            itemBuilder: (context, index) {
              final azienda = aziende[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(azienda.name),
                  subtitle: Text(
                    'Paga: €${azienda.hourlyRate.toStringAsFixed(2)}/h - Straordinario: €${azienda.overtimeRate.toStringAsFixed(2)}/h',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        onPressed: () =>
                            _showAddCompanyDialog(azienda: azienda),
                        tooltip: 'Modifica',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteCompany(azienda.id!),
                        tooltip: 'Elimina',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCompanyDialog,
        tooltip: 'Aggiungi Azienda',
        child: const Icon(Icons.add),
      ),
    );
  }
}
