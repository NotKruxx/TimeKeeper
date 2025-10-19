// lib/ui/pages/add_hours_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../api/database_api.dart';
import '../../models/azienda.dart';
import '../../models/hours_worked.dart';
import '../../utils/time_rounder.dart';

class AddHoursPage extends StatefulWidget {
  const AddHoursPage({super.key});
  @override
  State<AddHoursPage> createState() => _AddHoursPageState();
}

class _AddHoursPageState extends State<AddHoursPage> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseApi _dbApi = DatabaseApi();
  List<Azienda> _aziende = [];
  Azienda? _selectedAzienda;
  DateTime? _startTime;
  DateTime? _endTime;
  final _lunchBreakController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAziende();
  }

  Future<void> _loadAziende() async {
    final aziendeList = await _dbApi.getAziende();
    if (mounted) {
      setState(() {
        _aziende = aziendeList;
        if (_aziende.isNotEmpty) _selectedAzienda = _aziende.first;
      });
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart)
        _startTime = dateTime;
      else
        _endTime = dateTime;
    });
    _formKey.currentState?.validate();
  }

  Future<void> _saveHours() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final roundedStartTime = roundToNearestHalfHour(_startTime!);
    final roundedEndTime = roundToNearestHalfHour(_endTime!);
    final lunchInMinutes = int.tryParse(_lunchBreakController.text) ?? 0;

    final newHours = HoursWorked(
      aziendaId: _selectedAzienda!.id!,
      startTime: roundedStartTime,
      endTime: roundedEndTime,
      lunchBreak: lunchInMinutes,
      notes: _notesController.text,
    );

    final isOverlapping = await _dbApi.checkOverlap(newHours);

    if (!mounted) return;

    if (isOverlapping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Errore: l\'orario si sovrappone con un altro già salvato.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      await _dbApi.addHoursWorked(newHours);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ore salvate con successo!')),
      );
      setState(() {
        _formKey.currentState!.reset();
        _startTime = null;
        _endTime = null;
        _lunchBreakController.text = '0';
        _notesController.clear();
        if (_aziende.isNotEmpty) _selectedAzienda = _aziende.first;
      });
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aggiungi Ore')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_aziende.isNotEmpty)
                DropdownButtonFormField<Azienda>(
                  value: _selectedAzienda,
                  decoration: const InputDecoration(labelText: 'Azienda'),
                  items: _aziende
                      .map(
                        (a) => DropdownMenuItem(value: a, child: Text(a.name)),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedAzienda = val),
                  validator: (value) =>
                      value == null ? 'Seleziona un\'azienda' : null,
                )
              else
                const Center(
                  child: Text(
                    "Nessuna azienda trovata. Vai alla sezione 'Aziende' per aggiungerne una.",
                  ),
                ),
              const SizedBox(height: 20),
              _buildDateTimePicker(
                label: 'Inizio Lavoro',
                dateTime: _startTime,
                onTap: () => _pickDateTime(true),
                validator: (value) {
                  if (value == null)
                    return 'Per favore, inserisci un orario di inizio.';
                  if (value.isAfter(DateTime.now()))
                    return 'L\'orario non può essere nel futuro.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildDateTimePicker(
                label: 'Fine Lavoro',
                dateTime: _endTime,
                onTap: () => _pickDateTime(false),
                validator: (value) {
                  if (value == null)
                    return 'Per favore, inserisci un orario di fine.';
                  if (_startTime != null && value.isBefore(_startTime!)) {
                    return 'La fine non può essere prima dell\'inizio.';
                  }
                  if (_startTime != null &&
                      value.difference(_startTime!).inHours > 24) {
                    return 'Un turno non può durare più di 24 ore.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lunchBreakController,
                decoration: const InputDecoration(
                  labelText: 'Pausa (minuti)',
                  suffixText: 'min',
                ),
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
                onPressed:
                    (_startTime == null ||
                        _endTime == null ||
                        _selectedAzienda == null ||
                        _isSaving)
                    ? null
                    : _saveHours,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
                    : const Text('Salva Ore'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    DateTime? dateTime,
    required VoidCallback onTap,
    String? Function(DateTime?)? validator,
  }) {
    final key = GlobalKey<FormFieldState<DateTime>>();
    return FormField<DateTime>(
      key: key,
      initialValue: dateTime,
      validator: validator,
      builder: (FormFieldState<DateTime> state) {
        if (dateTime != state.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            state.didChange(dateTime);
          });
        }
        return InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              errorText: state.errorText,
            ),
            child: Text(
              dateTime == null
                  ? 'Seleziona data e ora'
                  : DateFormat('dd/MM/yyyy HH:mm').format(dateTime),
            ),
          ),
        );
      },
    );
  }
}
