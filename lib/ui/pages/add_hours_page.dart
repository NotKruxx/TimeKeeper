// lib/ui/pages/add_hours_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/service/supabase_service.dart';
import '../providers/data_cache_provider.dart';
import '../../data/models/azienda_model.dart';
import '../../data/models/hours_worked_model.dart';
import '../../data/services/settings_service.dart';
import '../../utils/time_rounder.dart';

class AddHoursPage extends StatefulWidget {
  const AddHoursPage({super.key});

  @override
  State<AddHoursPage> createState() => _AddHoursPageState();
}

class _AddHoursPageState extends State<AddHoursPage> {
  final _formKey         = GlobalKey<FormState>();
  final _lunchController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  AziendaModel?  _selectedAzienda;
  DateTime?      _startTime;
  DateTime?      _endTime;
  bool           _isSaving = false;

  @override
  void dispose() {
    _lunchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── date/time picker ───────────────────────────────────────────────────────
  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => isStart ? _startTime = dt : _endTime = dt);
    _formKey.currentState?.validate();
  }

  // ── save ───────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final round = SettingsService.instance.roundTimes;
      final start = round ? roundToNearestHalfHour(_startTime!) : _startTime!;
      final end   = round ? roundToNearestHalfHour(_endTime!)   : _endTime!;

      final uid = SupabaseService.instance.uid;
      if (uid == null) throw Exception("Utente non loggato");

      final model = HoursWorkedModel.create(
        userId: uid,
        aziendaUuid: _selectedAzienda!.uuid,
        startTime: start,
        endTime: end,
        lunchBreak: int.tryParse(_lunchController.text) ?? 0,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      await context.read<DataCacheProvider>().saveHour(model);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ore salvate!')),
      );
      _reset();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Errore imprevisto: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _reset() {
    _formKey.currentState?.reset();
    _lunchController.text = '0';
    _notesController.clear();
    setState(() {
      _startTime = null;
      _endTime   = null;
      _selectedAzienda = null; // Resetta anche l'azienda
    });
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Ora leggiamo dalla cache ultra-veloce invece del vecchio provider
    final aziende = context.watch<DataCacheProvider>().aziende;

    // Se c'è un'azienda selezionata ma non esiste più nella lista (es. è stata eliminata), resettiamola.
    if (_selectedAzienda != null && !aziende.contains(_selectedAzienda)) {
      _selectedAzienda = null;
    }

    // Se non abbiamo ancora selezionato nulla e c'è almeno un'azienda, auto-selezioniamo la prima.
    if (_selectedAzienda == null && aziende.isNotEmpty) {
      _selectedAzienda = aziende.first;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Aggiungi Ore')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (aziende.isEmpty)
                const _EmptyAziendeHint()
              else
                DropdownButtonFormField<AziendaModel>(
                  value: _selectedAzienda,
                  decoration: const InputDecoration(labelText: 'Azienda'),
                  items: aziende
                      .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedAzienda = v),
                  validator: (v) => v == null ? "Seleziona un'azienda" : null,
                ),
              const SizedBox(height: 20),
              _DateTimeField(
                label: 'Inizio Lavoro',
                value: _startTime,
                onTap: () => _pickDateTime(true),
                validator: (v) {
                  if (v == null) return 'Inserisci un orario di inizio.';
                  if (v.isAfter(DateTime.now())) return "L'orario non può essere nel futuro.";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _DateTimeField(
                label: 'Fine Lavoro',
                value: _endTime,
                onTap: () => _pickDateTime(false),
                validator: (v) {
                  if (v == null) return 'Inserisci un orario di fine.';
                  if (_startTime != null && v.isBefore(_startTime!)) return "La fine non può essere prima dell'inizio.";
                  if (_startTime != null && v.difference(_startTime!).inHours > 24) return 'Un turno non può durare più di 24 ore.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lunchController,
                decoration: const InputDecoration(labelText: 'Pausa (minuti)', suffixText: 'min'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: 3,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: (_startTime == null || _endTime == null || _selectedAzienda == null || _isSaving)
                    ? null
                    : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSaving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Text('Salva Ore', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── reusable date/time form field ─────────────────────────────────────────────

class _DateTimeField extends FormField<DateTime> {
  _DateTimeField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    super.validator,
  }) : super(
          initialValue: value,
          builder: (state) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (value != state.value) state.didChange(value);
            });
            return InkWell(
              onTap: onTap,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  errorText: state.errorText,
                ),
                child: Text(
                  value == null
                      ? 'Seleziona data e ora'
                      : DateFormat('dd/MM/yyyy HH:mm').format(value),
                ),
              ),
            );
          },
        );
}

class _EmptyAziendeHint extends StatelessWidget {
  const _EmptyAziendeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.withAlpha(50)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.teal),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Nessuna azienda trovata. Vai alla sezione 'Aziende' per aggiungerne una.",
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}