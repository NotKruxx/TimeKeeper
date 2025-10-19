// lib/ui/pages/scan_page.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../api/database_api.dart';
import '../../models/azienda.dart';
import '../../models/hours_worked.dart';

enum ScanStatus { scanning, processing, success, failure }

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final DatabaseApi _dbApi = DatabaseApi();
  List<Azienda> _aziende = [];
  Azienda? _selectedAzienda;
  ScanStatus _status = ScanStatus.scanning;
  DateTime? _pendingStartTime;
  String? _pendingAziendaName;
  final String _qrCodeKey = "IL_MIO_CODICE_SPECIALE_PER_TIMBRARE";

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadAziende();
    await _loadPendingCheckin();
  }

  Future<void> _loadAziende() async {
    final aziendeList = await _dbApi.getAziende();
    if (mounted) {
      setState(() {
        _aziende = aziendeList;
        if (_aziende.isNotEmpty) {
          _selectedAzienda = _aziende.first;
        }
      });
    }
  }

  Future<void> _loadPendingCheckin() async {
    final prefs = await SharedPreferences.getInstance();
    final startTimeString = prefs.getString('checkin_start_time');
    final aziendaId = prefs.getInt('checkin_azienda_id');
    if (startTimeString != null && aziendaId != null) {
      final pendingAzienda = _aziende
          .where((a) => a.id == aziendaId)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _pendingStartTime = DateTime.parse(startTimeString);
          _pendingAziendaName = pendingAzienda?.name ?? 'Sconosciuta';
        });
      }
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_status != ScanStatus.scanning) return;
    setState(() => _status = ScanStatus.processing);

    final String? scannedCode = capture.barcodes.first.rawValue;
    if (scannedCode != _qrCodeKey) {
      _setFeedback(ScanStatus.failure, "Codice QR non valido.");
      return;
    }
    if (_selectedAzienda == null && _pendingStartTime == null) {
      _setFeedback(ScanStatus.failure, "Per favore, seleziona un'azienda.");
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final startTimeString = prefs.getString('checkin_start_time');
      if (startTimeString == null) {
        final now = DateTime.now();
        await prefs.setString('checkin_start_time', now.toIso8601String());
        await prefs.setInt('checkin_azienda_id', _selectedAzienda!.id!);
        if (mounted) {
          setState(() {
            _pendingStartTime = now;
            _pendingAziendaName = _selectedAzienda!.name;
          });
        }
        _setFeedback(
          ScanStatus.success,
          "Check-in registrato per ${_selectedAzienda!.name}!",
        );
      } else {
        final startTime = DateTime.parse(startTimeString);
        final aziendaId = prefs.getInt('checkin_azienda_id');
        final endTime = DateTime.now();
        if (aziendaId == null) throw Exception("ID azienda non trovato.");

        final newHours = HoursWorked(
          aziendaId: aziendaId,
          startTime: startTime,
          endTime: endTime,
          lunchBreak: 0,
          notes: 'Registrato tramite QR Code',
        );

        await _dbApi.addHoursWorked(newHours);
        await prefs.remove('checkin_start_time');
        await prefs.remove('checkin_azienda_id');
        if (mounted) {
          setState(() {
            _pendingStartTime = null;
            _pendingAziendaName = null;
          });
        }
        _setFeedback(
          ScanStatus.success,
          "Check-out registrato. Turno salvato!",
        );
      }
    } catch (e) {
      _setFeedback(
        ScanStatus.failure,
        "Si è verificato un errore: ${e.toString()}",
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        setState(() {
          _pendingStartTime = null;
          _pendingAziendaName = null;
        });
      }
    }
  }

  void _setFeedback(ScanStatus status, String message) {
    if (!mounted) return;
    setState(() => _status = status);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: status == ScanStatus.success
            ? Colors.green
            : Colors.red,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _status = ScanStatus.scanning);
    });
  }

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    switch (_status) {
      case ScanStatus.success:
        borderColor = Colors.green;
        break;
      case ScanStatus.failure:
        borderColor = Colors.red;
        break;
      default:
        borderColor = Theme.of(context).colorScheme.primary;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Scansiona per Timbrare')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Opacity(
              opacity: _pendingStartTime != null ? 0.5 : 1.0,
              child: _aziende.isNotEmpty
                  ? DropdownButtonFormField<Azienda>(
                      value: _selectedAzienda,
                      decoration: const InputDecoration(
                        labelText: 'Azienda Corrente',
                      ),
                      items: _aziende
                          .map(
                            (a) =>
                                DropdownMenuItem(value: a, child: Text(a.name)),
                          )
                          .toList(),
                      onChanged: _pendingStartTime != null
                          ? null
                          : (val) => setState(() => _selectedAzienda = val),
                      isExpanded: true,
                    )
                  : Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withAlpha(75)),
                      ),
                      child: const Center(
                        child: Text(
                          "Nessuna azienda trovata.\nVai alla sezione 'Aziende' per aggiungerne una.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(onDetect: _handleScan),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildScanIcon(),
                  ),
                ),
              ],
            ),
          ),
          _buildPendingCheckinCard(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text(
              'Inquadra il codice QR per registrare l\'inizio o la fine del turno.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanIcon() {
    switch (_status) {
      case ScanStatus.scanning:
        return const SizedBox.shrink(key: ValueKey('scanning'));
      case ScanStatus.processing:
        return const Center(
          key: ValueKey('processing'),
          child: CircularProgressIndicator(color: Colors.white),
        );
      case ScanStatus.success:
        return const Icon(
          key: ValueKey('success'),
          Icons.check_circle,
          color: Colors.green,
          size: 100,
        );
      case ScanStatus.failure:
        return const Icon(
          key: ValueKey('failure'),
          Icons.cancel,
          color: Colors.red,
          size: 100,
        );
    }
  }

  Widget _buildPendingCheckinCard() {
    if (_pendingStartTime == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 4,
        child: ListTile(
          leading: const Icon(Icons.timer_outlined, color: Colors.tealAccent),
          title: Text(
            'Turno in corso per: ${_pendingAziendaName ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Check-in effettuato alle: ${DateFormat('HH:mm:ss', 'it_IT').format(_pendingStartTime!)}',
          ),
        ),
      ),
    );
  }
}
