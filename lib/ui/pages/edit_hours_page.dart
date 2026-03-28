// lib/ui/pages/edit_hours_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/azienda_repository.dart';
import '../../data/repositories/hours_repository.dart';
import '../../data/services/settings_service.dart';
import '../../models/azienda.dart';
import '../../models/hours_worked.dart';
import '../../ui/providers/dashboard_provider.dart';
import '../../utils/time_rounder.dart';

class EditHoursPage extends StatefulWidget {
  final HoursWorked hourToEdit;
  const EditHoursPage({super.key, required this.hourToEdit});

  @override
  State<EditHoursPage> createState() => _EditHoursPageState();
}

class _EditHoursPageState extends State<EditHoursPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _lunchCtrl;
  late TextEditingController _notesCtrl;

  List<Azienda> _aziende = [];
  Azienda? _selectedAzienda;
  late DateTime _startTime;
  late DateTime _endTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _startTime = widget.hourToEdit.startTime;
    _endTime = widget.hourToEdit.endTime;
    _lunchCtrl =
        TextEditingController(text: widget.hourToEdit.lunchBreak.toString());
    _notesCtrl =
        TextEditingController(text: widget.hourToEdit.notes ?? '');
    _loadAziende();
  }

  @override
  void dispose() {
    _lunchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAziende() async {
    final list = AziendaRepository.instance.getAll();
    if (!mounted) return;

    setState(() {
      _aziende = list;

      _selectedAzienda = list.firstWhere(
        (a) => a.uuid == widget.hourToEdit.aziendaUuid,
        orElse: () => list.first,
      );
    });
  }

  Future<void> _pickDateTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() => isStart ? _startTime = dt : _endTime = dt);
    _formKey.currentState?.validate();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedAzienda?.uuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore: azienda non valida')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final round = SettingsService.instance.roundTimes;

      final start =
          round ? roundToNearestHalfHour(_startTime) : _startTime;
      final end =
          round ? roundToNearestHalfHour(_endTime) : _endTime;

      final updated = widget.hourToEdit.copyWith(
        aziendaUuid: _selectedAzienda!.uuid!,
        startTime: start,
        endTime: end,
        lunchBreak: int.tryParse(_lunchCtrl.text) ?? 0,
        notes: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
      );

      if (HoursRepository.instance.hasOverlap(updated)) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("L'orario si sovrappone con un turno già salvato."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await HoursRepository.instance.update(updated);

      if (!mounted) return;

      context.read<DashboardProvider>().load();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orario aggiornato!')),
      );

      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifica Orario')),
      body: _selectedAzienda == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<Azienda>(
                      value: _selectedAzienda,
                      decoration:
                          const InputDecoration(labelText: 'Azienda'),
                      items: _aziende
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(a.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedAzienda = v),
                      validator: (v) =>
                          v == null ? "Seleziona un'azienda" : null,
                    ),
                    const SizedBox(height: 20),
                    _DateTimeTile(
                      label: 'Inizio Lavoro',
                      value: _startTime,
                      onTap: () => _pickDateTime(true),
                      validator: (v) {
                        if (v == null) {
                          return 'Inserisci un orario di inizio.';
                        }
                        if (v.isAfter(DateTime.now())) {
                          return "L'orario non può essere nel futuro.";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _DateTimeTile(
                      label: 'Fine Lavoro',
                      value: _endTime,
                      onTap: () => _pickDateTime(false),
                      validator: (v) {
                        if (v == null) {
                          return 'Inserisci un orario di fine.';
                        }
                        if (v.isBefore(_startTime)) {
                          return "La fine non può essere prima dell'inizio.";
                        }
                        if (v.difference(_startTime).inHours > 24) {
                          return 'Turno troppo lungo (max 24h).';
                        }
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
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Note'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
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

class _DateTimeTile extends FormField<DateTime> {
  _DateTimeTile({
    required String label,
    required DateTime value,
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
                  DateFormat('dd/MM/yyyy HH:mm').format(value),
                ),
              ),
            );
          },
        );
}