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

  Future<void> _openCompanyEditor({Azienda? azienda}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CompanyEditorPage(azienda: azienda)),
    );
    if (result == true) {
      _refreshAziende();
    }
  }

  Future<void> _deleteCompany(int id) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Conferma eliminazione"),
              content: const Text("Sei sicuro di voler eliminare questa azienda e tutti i suoi turni? L'azione è irreversibile."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annulla")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true), 
                  child: const Text("Elimina", style: TextStyle(color: Colors.white)),
                ),
              ],
            ));

    if (confirm == true) {
      await _dbApi.deleteAzienda(id);
      _refreshAziende();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestisci Aziende')),
      body: FutureBuilder<List<Azienda>>(
        future: _aziendeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Errore: ${snapshot.error}'));
          final aziende = snapshot.data ?? [];
          if (aziende.isEmpty) return const Center(child: Text('Nessuna azienda trovata. Tocca + per aggiungerne una.'));
          
          return ListView.builder(
            itemCount: aziende.length,
            itemBuilder: (context, index) {
              final azienda = aziende[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(azienda.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Paga: €${azienda.hourlyRate.toStringAsFixed(2)}/h - Straordinario: €${azienda.overtimeRate.toStringAsFixed(2)}/h'),
                      Text(
                        "Orario: ${azienda.scheduleConfig.start.format(context)} - ${azienda.scheduleConfig.end.format(context)}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (azienda.scheduleConfig.enabled)
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 14, color: Colors.tealAccent),
                            SizedBox(width: 4),
                            Text("Turni automatici attivi", style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
                          ],
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.orange), onPressed: () => _openCompanyEditor(azienda: azienda)),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteCompany(azienda.id!)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCompanyEditor(),
        tooltip: 'Aggiungi Azienda',
        child: const Icon(Icons.add),
      ),
    );
  }
}


class CompanyEditorPage extends StatefulWidget {
  final Azienda? azienda;
  const CompanyEditorPage({super.key, this.azienda});

  @override
  State<CompanyEditorPage> createState() => _CompanyEditorPageState();
}

class _CompanyEditorPageState extends State<CompanyEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rateController = TextEditingController();
  final _overtimeController = TextEditingController();
  final _breakController = TextEditingController();

  bool _autoEnabled = false;
  TimeOfDay _autoStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _autoEnd = const TimeOfDay(hour: 17, minute: 0);
  List<int> _selectedDays = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    if (widget.azienda != null) {
      _nameController.text = widget.azienda!.name;
      _rateController.text = widget.azienda!.hourlyRate.toStringAsFixed(2);
      _overtimeController.text = widget.azienda!.overtimeRate.toStringAsFixed(2);
      final config = widget.azienda!.scheduleConfig;
      _autoEnabled = config.enabled;
      _autoStart = config.start;
      _autoEnd = config.end;
      _selectedDays = List.from(config.activeDays);
      _breakController.text = config.lunchBreakMinutes.toString();
    } else {
      _breakController.text = "60";
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _autoStart : _autoEnd;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) _autoStart = picked;
        else _autoEnd = picked;
      });
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        if (_selectedDays.length > 1) _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final hourlyRate = double.tryParse(_rateController.text) ?? 0.0;
      final overtimeRate = double.tryParse(_overtimeController.text) ?? hourlyRate;
      final lunchBreak = int.tryParse(_breakController.text) ?? 0;

      String? automationStartDate;
      if (_autoEnabled) {
        if (widget.azienda == null || !widget.azienda!.scheduleConfig.enabled) {
          final now = DateTime.now();
          automationStartDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
        } else {
          automationStartDate = widget.azienda!.scheduleConfig.automationStartDate;
        }
      }

      final scheduleConfig = ScheduleConfig(
        enabled: _autoEnabled,
        start: _autoStart,
        end: _autoEnd,
        activeDays: _selectedDays,
        lunchBreakMinutes: lunchBreak,
        automationStartDate: automationStartDate,
      );

      final newAzienda = Azienda(
        id: widget.azienda?.id,
        name: name,
        hourlyRate: hourlyRate,
        overtimeRate: overtimeRate,
        scheduleConfig: scheduleConfig,
      );

      try {
        if (widget.azienda != null) {
          await DatabaseApi().updateAzienda(newAzienda);
        } else {
          await DatabaseApi().addAzienda(newAzienda);
        }
        await DatabaseApi().runAutoShiftGeneration();
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.azienda != null ? 'Modifica Azienda' : 'Nuova Azienda')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Azienda*', prefixIcon: Icon(Icons.business)),
              validator: (val) => val == null || val.isEmpty ? 'Il nome è obbligatorio' : null,
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _rateController,
                  decoration: const InputDecoration(labelText: 'Paga Oraria (€)', prefixIcon: Icon(Icons.euro)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _overtimeController,
                  decoration: const InputDecoration(labelText: 'Straordinario (€)', prefixIcon: Icon(Icons.trending_up)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                ),
              ),
            ]),
            const Divider(height: 40, thickness: 1),
            Text('Orario di Lavoro Standard', style: Theme.of(context).textTheme.titleMedium),
            const Text(
              'Definisce la fascia oraria per il calcolo di ore ordinarie e straordinari.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _timeButton("Inizio", _autoStart, () => _pickTime(true)),
                const Icon(Icons.arrow_right_alt, size: 32),
                _timeButton("Fine", _autoEnd, () => _pickTime(false)),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _breakController,
              decoration: const InputDecoration(labelText: 'Pausa Pranzo (minuti)', prefixIcon: Icon(Icons.timelapse)),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text("Giorni lavorativi:*", style: TextStyle(color: Colors.grey))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _dayChip(1, "Lun"), _dayChip(2, "Mar"), _dayChip(3, "Mer"),
                _dayChip(4, "Gio"), _dayChip(5, "Ven"), _dayChip(6, "Sab"), _dayChip(7, "Dom"),
              ],
            ),
            const Divider(height: 40, thickness: 1),
            Container(
              decoration: BoxDecoration(
                color: _autoEnabled ? Colors.teal.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _autoEnabled ? Colors.teal : Colors.grey.withOpacity(0.3)),
              ),
              child: SwitchListTile(
                title: const Text('Turni Automatici', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Abilita la generazione automatica dei turni passati per i giorni non registrati.'),
                value: _autoEnabled,
                onChanged: (val) => setState(() => _autoEnabled = val),
                secondary: Icon(Icons.auto_awesome, color: _autoEnabled ? Colors.tealAccent : Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.teal),
              child: const Text('SALVA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeButton(String label, TimeOfDay time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(time.format(context), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _dayChip(int day, String label) {
    final isSelected = _selectedDays.contains(day);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _toggleDay(day),
      showCheckmark: false,
      selectedColor: Colors.teal,
      backgroundColor: Colors.black.withOpacity(0.2),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}