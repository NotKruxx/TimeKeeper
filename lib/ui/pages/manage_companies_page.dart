// lib/ui/pages/manage_companies_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/azienda.dart';
import '../../ui/providers/companies_provider.dart';

class ManageCompaniesPage extends StatelessWidget {
  const ManageCompaniesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CompaniesProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Gestisci Aziende')),
      body: p.isLoading
          ? const Center(child: CircularProgressIndicator())
          : p.aziende.isEmpty
              ? const Center(child: Text('Nessuna azienda. Tocca + per aggiungerne una.'))
              : ListView.builder(
                  itemCount: p.aziende.length,
                  itemBuilder: (_, i) => _CompanyTile(
                    azienda: p.aziende[i],
                    onEdit: () => _openEditor(context, p.aziende[i]),
                    onDelete: () => _confirmDelete(context, p, p.aziende[i].id!),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Aggiungi Azienda',
        onPressed: () => _openEditor(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, Azienda? azienda) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompanyEditorPage(azienda: azienda)),
    );
    if (context.mounted) context.read<CompaniesProvider>().load();
  }

  Future<void> _confirmDelete(BuildContext context, CompaniesProvider p, int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: const Text("Elimina l'azienda e tutti i suoi turni? L'azione è irreversibile."),
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
    if (ok == true) await p.delete(id);
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.azienda, required this.onEdit, required this.onDelete});
  final Azienda azienda;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final cfg = azienda.scheduleConfig;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        title: Text(azienda.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('€${azienda.hourlyRate.toStringAsFixed(2)}/h  •  Straord. €${azienda.overtimeRate.toStringAsFixed(2)}/h'),
            Text(
              'Orario: ${cfg.start.format(context)} – ${cfg.end.format(context)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (cfg.enabled)
              const Row(children: [
                Icon(Icons.auto_awesome, size: 14, color: Colors.tealAccent),
                SizedBox(width: 4),
                Text('Turni automatici attivi', style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
              ]),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit,   color: Colors.orange), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red),    onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

// ── editor ────────────────────────────────────────────────────────────────────

class CompanyEditorPage extends StatefulWidget {
  final Azienda? azienda;
  const CompanyEditorPage({super.key, this.azienda});

  @override
  State<CompanyEditorPage> createState() => _CompanyEditorPageState();
}

class _CompanyEditorPageState extends State<CompanyEditorPage> {
  final _formKey          = GlobalKey<FormState>();
  final _nameCtrl         = TextEditingController();
  final _rateCtrl         = TextEditingController();
  final _overtimeCtrl     = TextEditingController();
  final _breakCtrl        = TextEditingController();

  bool       _autoEnabled  = false;
  TimeOfDay  _autoStart    = const TimeOfDay(hour: 8,  minute: 0);
  TimeOfDay  _autoEnd      = const TimeOfDay(hour: 17, minute: 0);
  List<int>  _activeDays   = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    final a = widget.azienda;
    if (a != null) {
      _nameCtrl.text     = a.name;
      _rateCtrl.text     = a.hourlyRate.toStringAsFixed(2);
      _overtimeCtrl.text = a.overtimeRate.toStringAsFixed(2);
      _autoEnabled       = a.scheduleConfig.enabled;
      _autoStart         = a.scheduleConfig.start;
      _autoEnd           = a.scheduleConfig.end;
      _activeDays        = List.from(a.scheduleConfig.activeDays);
      _breakCtrl.text    = a.scheduleConfig.lunchBreakMinutes.toString();
    } else {
      _breakCtrl.text = '60';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    _overtimeCtrl.dispose();
    _breakCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _autoStart : _autoEnd,
    );
    if (picked != null) setState(() => isStart ? _autoStart = picked : _autoEnd = picked);
  }

  void _toggleDay(int day) {
    setState(() {
      if (_activeDays.contains(day)) {
        if (_activeDays.length > 1) _activeDays.remove(day);
      } else {
        _activeDays.add(day);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    String? startDate;
    if (_autoEnabled) {
      if (widget.azienda == null || !widget.azienda!.scheduleConfig.enabled) {
        final n = DateTime.now();
        startDate = '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
      } else {
        startDate = widget.azienda!.scheduleConfig.automationStartDate;
      }
    }

    final updated = Azienda(
      id:           widget.azienda?.id,
      name:         _nameCtrl.text.trim(),
      hourlyRate:   double.tryParse(_rateCtrl.text) ?? 0.0,
      overtimeRate: double.tryParse(_overtimeCtrl.text) ?? 0.0,
      scheduleConfig: ScheduleConfig(
        enabled:              _autoEnabled,
        start:                _autoStart,
        end:                  _autoEnd,
        activeDays:           _activeDays,
        lunchBreakMinutes:    int.tryParse(_breakCtrl.text) ?? 0,
        automationStartDate:  startDate,
      ),
    );

    try {
      await context.read<CompaniesProvider>().save(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.azienda != null ? 'Modifica Azienda' : 'Nuova Azienda'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nome Azienda *', prefixIcon: Icon(Icons.business)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Il nome è obbligatorio' : null,
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _rateCtrl,
                decoration: const InputDecoration(labelText: 'Paga Oraria (€)', prefixIcon: Icon(Icons.euro)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              )),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(
                controller: _overtimeCtrl,
                decoration: const InputDecoration(labelText: 'Straordinario (€)', prefixIcon: Icon(Icons.trending_up)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              )),
            ]),
            const Divider(height: 40),
            Text('Orario Standard', style: Theme.of(context).textTheme.titleMedium),
            const Text('Soglia per il calcolo degli straordinari.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TimeButton(label: 'Inizio', time: _autoStart, onTap: () => _pickTime(true)),
                const Icon(Icons.arrow_right_alt, size: 32),
                _TimeButton(label: 'Fine',   time: _autoEnd,   onTap: () => _pickTime(false)),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _breakCtrl,
              decoration: const InputDecoration(labelText: 'Pausa Pranzo (min)', prefixIcon: Icon(Icons.timelapse)),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            const Text('Giorni lavorativi:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (day, lbl) in [(1,'Lun'),(2,'Mar'),(3,'Mer'),(4,'Gio'),(5,'Ven'),(6,'Sab'),(7,'Dom')])
                  _DayChip(
                    label: lbl,
                    selected: _activeDays.contains(day),
                    onTap: () => _toggleDay(day),
                  ),
              ],
            ),
            const Divider(height: 40),
            Container(
              decoration: BoxDecoration(
                color: (_autoEnabled ? Colors.teal : Colors.grey).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _autoEnabled ? Colors.teal : Colors.grey.withValues(alpha: 0.3)),
              ),
              child: SwitchListTile(
                title: const Text('Turni Automatici', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Genera automaticamente i turni passati per i giorni non registrati.'),
                value: _autoEnabled,
                onChanged: (v) => setState(() => _autoEnabled = v),
                secondary: Icon(Icons.auto_awesome, color: _autoEnabled ? Colors.tealAccent : Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal,
              ),
              child: const Text('SALVA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.time, required this.onTap});
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(time.format(context), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    selectedColor: Colors.teal,
    backgroundColor: Colors.black.withValues(alpha: 0.2),
    labelStyle: TextStyle(
      color: selected ? Colors.white : Colors.white70,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );
}
