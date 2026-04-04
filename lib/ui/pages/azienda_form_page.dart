// lib/ui/pages/azienda_form_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/azienda_model.dart';
import '../providers/data_cache_provider.dart';

class AziendaFormPage extends StatefulWidget {
  final AziendaModel? aziendaToEdit;

  const AziendaFormPage({super.key, this.aziendaToEdit});

  @override
  State<AziendaFormPage> createState() => _AziendaFormPageState();
}

class _AziendaFormPageState extends State<AziendaFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _overtimeCtrl = TextEditingController();
  final _lunchCtrl = TextEditingController(text: '60');

  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  
  // 1 = Lunedì, ..., 7 = Domenica
  final Set<int> _selectedDays = {1, 2, 3, 4, 5}; 
  bool _autoGenerate = false;

  final List<String> _dayNames = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

  @override
  void initState() {
    super.initState();
    if (widget.aziendaToEdit != null) {
      final az = widget.aziendaToEdit!;
      _nameCtrl.text = az.name;
      _rateCtrl.text = az.hourlyRate > 0 ? az.hourlyRate.toString() : '';
      _overtimeCtrl.text = az.overtimeRate > 0 ? az.overtimeRate.toString() : '';

      final conf = az.scheduleConfig;
      if (conf.isNotEmpty) {
        if (conf['start_time'] != null) _startTime = _parseTime(conf['start_time']);
        if (conf['end_time'] != null) _endTime = _parseTime(conf['end_time']);
        if (conf['lunch_break'] != null) _lunchCtrl.text = conf['lunch_break'].toString();
        if (conf['work_days'] != null) {
          _selectedDays.clear();
          _selectedDays.addAll(List<int>.from(conf['work_days']));
        }
        if (conf['auto_generate'] != null) _autoGenerate = conf['auto_generate'] as bool;
      }
    }
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) _startTime = picked;
        else _endTime = picked;
      });
    }
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore: Utente non loggato')),
      );
      return;
    }

    // --- NUOVA LOGICA PER LA DATA DI ATTIVAZIONE TURNI AUTOMATICI ---
    final oldConfig = widget.aziendaToEdit?.scheduleConfig ?? {};
    final wasAuto = oldConfig['auto_generate'] == true;
    String? autoGenerateSince = oldConfig['auto_generate_since'] as String?;

    if (_autoGenerate && !wasAuto) {
      // Se l'hai appena ACCESO, segnamo la data di OGGI in formato UTC
      autoGenerateSince = DateTime.now().toUtc().toIso8601String();
    } else if (!_autoGenerate) {
      // Se l'hai SPENTO, cancelliamo la data per evitare problemi futuri
      autoGenerateSince = null;
    } else if (_autoGenerate && wasAuto && autoGenerateSince == null) {
      // Caso limite: era già acceso in una vecchia versione dell'app ma mancava la data
      autoGenerateSince = DateTime.now().toUtc().toIso8601String();
    }
    // ----------------------------------------------------------------

    final scheduleConfig = {
      'start_time': _formatTime(_startTime),
      'end_time': _formatTime(_endTime),
      'lunch_break': int.tryParse(_lunchCtrl.text) ?? 60,
      'work_days': _selectedDays.toList()..sort(),
      'auto_generate': _autoGenerate,
      'auto_generate_since': autoGenerateSince, // Salviamo la data magica
    };

    AziendaModel model;
    if (widget.aziendaToEdit == null) {
      model = AziendaModel.create(
        userId: uid,
        name: _nameCtrl.text.trim(),
        hourlyRate: double.tryParse(_rateCtrl.text.replaceAll(',', '.')) ?? 0.0,
        overtimeRate: double.tryParse(_overtimeCtrl.text.replaceAll(',', '.')) ?? 0.0,
        scheduleConfig: scheduleConfig,
      );
    } else {
      model = AziendaModel(
        uuid: widget.aziendaToEdit!.uuid,
        userId: widget.aziendaToEdit!.userId,
        name: _nameCtrl.text.trim(),
        hourlyRate: double.tryParse(_rateCtrl.text.replaceAll(',', '.')) ?? 0.0,
        overtimeRate: double.tryParse(_overtimeCtrl.text.replaceAll(',', '.')) ?? 0.0,
        scheduleConfig: scheduleConfig,
        createdAt: widget.aziendaToEdit!.createdAt,
        updatedAt: DateTime.now().toUtc(),
        isSynced: false,
        syncAction: 'update',
      );
    }

    // Salvataggio nel DataCacheProvider (che lo manderà a Supabase)
    await context.read<DataCacheProvider>().saveAzienda(model);

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.aziendaToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Modifica Azienda' : 'Nuova Azienda'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // NOME AZIENDA
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome Azienda *',
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
              ),
              const SizedBox(height: 16),

              // PAGHE
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Paga Oraria (€)',
                        prefixIcon: Icon(Icons.euro),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _overtimeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Straordinario (€)',
                        prefixIcon: Icon(Icons.trending_up),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ORARIO STANDARD
              const Text('Orario Standard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Soglia per il calcolo degli straordinari.', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TimeBox(
                    label: 'Inizio',
                    time: _startTime,
                    onTap: () => _pickTime(true),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Icon(Icons.arrow_right_alt, color: Colors.grey),
                  ),
                  _TimeBox(
                    label: 'Fine',
                    time: _endTime,
                    onTap: () => _pickTime(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // PAUSA PRANZO
              TextFormField(
                controller: _lunchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pausa Pranzo (min)',
                  prefixIcon: Icon(Icons.timer),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),

              // GIORNI LAVORATIVI
              const Text('Giorni lavorativi:', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final dayNum = index + 1;
                  final isSelected = _selectedDays.contains(dayNum);
                  return ChoiceChip(
                    label: Text(_dayNames[index]),
                    selected: isSelected,
                    selectedColor: Colors.teal,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) _selectedDays.add(dayNum);
                        else _selectedDays.remove(dayNum);
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 32),

              // TURNI AUTOMATICI
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[800]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text('Turni Automatici', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Genera automaticamente i turni per i giorni non registrati a partire da oggi.', style: TextStyle(fontSize: 12)),
                  secondary: const Icon(Icons.auto_awesome),
                  activeColor: Colors.tealAccent,
                  value: _autoGenerate,
                  onChanged: (v) => setState(() => _autoGenerate = v),
                ),
              ),
              const SizedBox(height: 32),

              // PULSANTE SALVA
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('SALVA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget helper per i box degli orari (Inizio/Fine)
class _TimeBox extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeBox({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[700]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              time.format(context),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}