// lib/ui/pages/edit_hours_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Import per Supabase

import '../../core/service/supabase_service.dart'; // Import per uid
import '../providers/data_cache_provider.dart';
import '../../data/models/azienda_model.dart';
import '../../data/models/hours_worked_model.dart';
import '../../data/services/settings_service.dart';
import '../../utils/time_rounder.dart';

class EditHoursPage extends StatefulWidget {
  final HoursWorkedModel hourToEdit;
  const EditHoursPage({super.key, required this.hourToEdit});

  @override
  State<EditHoursPage> createState() => _EditHoursPageState();
}

class _EditHoursPageState extends State<EditHoursPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _lunchCtrl;
  late TextEditingController _notesCtrl;

  AziendaModel? _selectedAzienda;
  late DateTime _startTime;
  late DateTime _endTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Inizializziamo i valori del form con quelli del turno da modificare
    // Convertiamo le date UTC in ora locale per mostrarle correttamente all'utente
    _startTime = widget.hourToEdit.startTime.toLocal();
    _endTime = widget.hourToEdit.endTime.toLocal();
    _lunchCtrl = TextEditingController(text: widget.hourToEdit.lunchBreak.toString());
    _notesCtrl = TextEditingController(text: widget.hourToEdit.notes ?? '');
    
    // Deferiamo il caricamento delle aziende per avere il context disponibile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAziende();
    });
  }

  @override
  void dispose() {
    _lunchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _loadAziende() {
    if (!mounted) return;
    final list = context.read<DataCacheProvider>().aziende;
    AziendaModel? initialAzienda;
    try {
      initialAzienda = list.firstWhere((a) => a.uuid == widget.hourToEdit.aziendaUuid);
    } catch (_) {
      initialAzienda = list.isNotEmpty ? list.first : null;
    }
    setState(() {
      _selectedAzienda = initialAzienda;
    });
  }

  Future<void> _pickDateTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)), // Permetti di registrare il turno di oggi
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => isStart ? _startTime = dt : _endTime = dt);
    _formKey.currentState?.validate();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAzienda == null) return;

    setState(() => _isSaving = true);

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Utente non autenticato');

      final round = SettingsService.instance.roundTimes;
      final start = round ? roundToNearestHalfHour(_startTime) : _startTime;
      final end   = round ? roundToNearestHalfHour(_endTime)   : _endTime;

      // --- LOGICA DI EREDITARIETÀ DELLA NOTA PER EVITARE DUPLICATI ---
      String? finalNotes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      // Se il turno originale era automatico E l'utente non ha scritto una nuova nota,
      // manteniamo la nota "speciale" per evitare che il motore lo rigeneri.
      if (widget.hourToEdit.notes == 'Turno generato automaticamente' && finalNotes == null) {
        finalNotes = 'Turno generato automaticamente';
      }
      // ---------------------------------------------------------------

      final updatedModel = widget.hourToEdit.copyWith(
        aziendaUuid: _selectedAzienda!.uuid,
        startTime:   start, // Il modello lo convertirà in UTC
        endTime:     end,
        lunchBreak:  int.tryParse(_lunchCtrl.text) ?? 0,
        notes:       finalNotes,
        isSynced:    false,
        syncAction:  'update',
      );

      await context.read<DataCacheProvider>().saveHour(updatedModel);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turno aggiornato!')),
      );
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

  @override
  Widget build(BuildContext context) {
    // Carichiamo le aziende dal DataCacheProvider
    final aziende = context.watch<DataCacheProvider>().aziende;

    return Scaffold(
      appBar: AppBar(title: const Text('Modifica Orario')),
      body: aziende.isEmpty
          ? const Center(child: Text("Nessuna azienda disponibile."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<AziendaModel>(
                      value: _selectedAzienda,
                      decoration: const InputDecoration(labelText: 'Azienda'),
                      items: aziende
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(a.name),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedAzienda = v),
                      validator: (v) => v == null ? "Seleziona un'azienda" : null,
                    ),
                    const SizedBox(height: 20),
                    _DateTimeTile(
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
                    _DateTimeTile(
                      label: 'Fine Lavoro',
                      value: _endTime,
                      onTap: () => _pickDateTime(false),
                      validator: (v) {
                        if (v == null) return 'Inserisci un orario di fine.';
                        if (v.isBefore(_startTime)) return "La fine non può essere prima dell'inizio.";
                        if (v.difference(_startTime).inHours > 24) return 'Turno troppo lungo (max 24h).';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lunchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pausa (minuti)',
                        suffixText: 'min',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Note'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            )
                          : const Text('Salva Modifiche'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _DateTimeTile extends FormField<DateTime?> {
  _DateTimeTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    super.validator,
  }) : super(
          initialValue: value,
          autovalidateMode: AutovalidateMode.onUserInteraction,
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