// lib/ui/pages/edit_hours_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../api/database_api.dart';
import '../../models/azienda.dart';
import '../../models/hours_worked.dart';

class EditHoursPage extends StatefulWidget {
  final HoursWorked hourToEdit;
  const EditHoursPage({super.key, required this.hourToEdit});
  @override
  State<EditHoursPage> createState() => _EditHoursPageState();
}

class _EditHoursPageState extends State<EditHoursPage> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseApi _dbApi = DatabaseApi();
  List<Azienda> _aziende = [];
  late Azienda? _selectedAzienda;
  late DateTime _startTime;
  late DateTime _endTime;
  late final TextEditingController _lunchBreakController;
  late final TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _startTime = widget.hourToEdit.startTime;
    _endTime = widget.hourToEdit.endTime;
    _lunchBreakController = TextEditingController(
      text: widget.hourToEdit.lunchBreak.toString(),
    );
    _notesController = TextEditingController(text: widget.hourToEdit.notes);
    _loadAziende();
  }

  Future<void> _loadAziende() async {
    final aziendeList = await _dbApi.getAziende();
    if (mounted) {
      setState(() {
        _aziende = aziendeList;
        _selectedAzienda = _aziende.firstWhere(
          (a) => a.id == widget.hourToEdit.aziendaId,
          orElse: () => _aziende.first,
        );
      });
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startTime : _endTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStart ? _startTime : _endTime),
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

  Future<void> _updateHours() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final lunchInMinutes = int.tryParse(_lunchBreakController.text) ?? 0;
    final updatedHour = HoursWorked(
      id: widget.hourToEdit.id,
      aziendaId: _selectedAzienda!.id!,
      startTime: _startTime,
      endTime: _endTime,
      lunchBreak: lunchInMinutes,
      notes: _notesController.text,
    );

    final isOverlapping = await _dbApi.checkOverlap(updatedHour);
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
      await _dbApi.updateHoursWorked(updatedHour);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orario aggiornato con successo!')),
      );
      Navigator.of(context).pop();
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifica Orario')),
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
                  if (value.isBefore(_startTime)) {
                    return 'La fine non può essere prima dell\'inizio.';
                  }
                  if (value.difference(_startTime).inHours > 24) {
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
                onPressed: _isSaving ? null : _updateHours,
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
                    : const Text('Salva Modifiche'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    required DateTime dateTime,
    required VoidCallback onTap,
    String? Function(DateTime?)? validator,
  }) {
    final key = GlobalKey<FormFieldState<DateTime>>();
    return FormField<DateTime>(
      key: key,
      autovalidateMode: AutovalidateMode.onUserInteraction,
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
            child: Text(DateFormat('dd/MM/yyyy HH:mm').format(dateTime)),
          ),
        );
      },
    );
  }
}
