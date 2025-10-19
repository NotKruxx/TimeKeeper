// lib/ui/pages/dashboard_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../api/database_api.dart';
import '../../models/hours_worked.dart';
import '../../models/azienda.dart';
import 'edit_hours_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DatabaseApi _dbApi = DatabaseApi();
  String? _selectedMonth;
  Azienda? _selectedAzienda;
  List<String> _availableMonths = [];
  List<HoursWorked> _hours = [];
  List<Azienda> _aziende = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final allHours = await _dbApi.getHoursWorked();
    final months = allHours
        .map((h) => DateFormat('MMMM yyyy', 'it_IT').format(h.startTime))
        .toSet()
        .toList();
    months.sort(
      (a, b) => DateFormat(
        'MMMM yyyy',
        'it_IT',
      ).parse(b).compareTo(DateFormat('MMMM yyyy', 'it_IT').parse(a)),
    );
    final aziendeList = await _dbApi.getAziende();
    if (mounted) {
      setState(() {
        _availableMonths = months;
        _aziende = aziendeList;
        if (_availableMonths.isNotEmpty && _selectedMonth == null) {
          _selectedMonth = _availableMonths.first;
        }
        if (_aziende.isNotEmpty && _selectedAzienda == null) {
          _selectedAzienda = _aziende.first;
        }
      });
    }
    await _filterHours();
  }

  Future<void> _filterHours() async {
    final allHours = await _dbApi.getHoursWorked();
    if (mounted) {
      setState(() {
        _hours = allHours.where((h) {
          final monthMatch = _selectedMonth == null
              ? true
              : DateFormat('MMMM yyyy', 'it_IT').format(h.startTime) ==
                    _selectedMonth;
          final aziendaMatch = _selectedAzienda == null
              ? true
              : h.aziendaId == _selectedAzienda!.id;
          return monthMatch && aziendaMatch;
        }).toList();
        _hours.sort((a, b) => b.startTime.compareTo(a.startTime));
      });
    }
  }

  double _calculateHours(HoursWorked h) {
    return h.endTime.difference(h.startTime).inMinutes / 60.0 -
        h.lunchBreak / 60.0;
  }

  double _calculateOrdinaryHours(HoursWorked h) {
    double totalHours = _calculateHours(h);
    return totalHours > 8 ? 8 : (totalHours < 0 ? 0 : totalHours);
  }

  double _calculateOvertime(HoursWorked h) {
    double totalHours = _calculateHours(h);
    return totalHours > 8 ? totalHours - 8 : 0;
  }

  double get totaleOrdinary =>
      _hours.fold(0.0, (sum, h) => sum + _calculateOrdinaryHours(h));
  double get totaleOvertime =>
      _hours.fold(0.0, (sum, h) => sum + _calculateOvertime(h));

  double get totalEarnings {
    if (_aziende.isEmpty) return 0.0;
    double total = 0.0;
    for (var h in _hours) {
      final azienda = _aziende.firstWhere(
        (a) => a.id == h.aziendaId,
        orElse: () => Azienda(name: 'N/A'),
      );
      if (azienda.name != 'N/A') {
        final ordinaryHours = _calculateOrdinaryHours(h);
        final overtimeHours = _calculateOvertime(h);
        total += (ordinaryHours * azienda.hourlyRate);
        total += (overtimeHours * azienda.overtimeRate);
      }
    }
    return total;
  }

  Map<String, double> _groupedHoursByDay() {
    final Map<String, double> dailyHours = {};
    for (var h in _hours) {
      String day = DateFormat('dd/MM').format(h.startTime);
      dailyHours[day] = (dailyHours[day] ?? 0) + _calculateHours(h);
    }
    return dailyHours;
  }

  Future<void> _exportToCsv() async {
    if (_hours.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nessun dato da esportare per il filtro selezionato.',
            ),
          ),
        );
      }
      return;
    }
    List<List<dynamic>> rows = [];
    rows.add([
      'Azienda',
      'Data',
      'Inizio',
      'Fine',
      'Pausa (min)',
      'Ore Ordinarie',
      'Ore Straordinario',
      'Note',
    ]);
    for (var h in _hours) {
      final azienda = _aziende.firstWhere(
        (a) => a.id == h.aziendaId,
        orElse: () => Azienda(name: 'N/A'),
      );
      rows.add([
        azienda.name,
        DateFormat('dd/MM/yyyy').format(h.startTime),
        DateFormat('HH:mm').format(h.startTime),
        DateFormat('HH:mm').format(h.endTime),
        h.lunchBreak,
        _calculateOrdinaryHours(h).toStringAsFixed(2),
        _calculateOvertime(h).toStringAsFixed(2),
        h.notes ?? '',
      ]);
    }
    String csv = const ListToCsvConverter().convert(rows);
    final directory = await getTemporaryDirectory();
    final filterText = _selectedAzienda != null
        ? _selectedAzienda!.name.replaceAll(' ', '_')
        : 'tutte';
    final path =
        '${directory.path}/report_ore_${_selectedMonth?.replaceAll(' ', '_')}_$filterText.csv';
    final file = File(path);
    await file.writeAsString(csv);
    await Share.shareXFiles([
      XFile(path),
    ], text: 'Report ore lavorate per $_selectedMonth');
  }

  Future<void> _deleteHour(HoursWorked h) async {
    if (h.id == null) {
      return;
    }
    await _dbApi.deleteHour(h.id!);
    await _loadData();
  }

  void _editHour(HoursWorked h) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (context) => EditHoursPage(hourToEdit: h)),
        )
        .then((_) {
          _loadData();
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedAzienda != null && !_aziende.contains(_selectedAzienda)) {
      _selectedAzienda = _aziende.isNotEmpty ? _aziende.first : null;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportToCsv,
            tooltip: 'Esporta in CSV',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilters(),
              const SizedBox(height: 24),
              _buildStatsCards(),
              const SizedBox(height: 24),
              _buildChart(),
              const SizedBox(height: 24),
              Text(
                'Dettaglio Ore',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _buildHoursDataTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_aziende.isNotEmpty)
          DropdownButton<Azienda>(
            value: _selectedAzienda,
            items: _aziende
                .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                .toList(),
            onChanged: (val) {
              setState(() => _selectedAzienda = val);
              _filterHours();
            },
          ),
        if (_availableMonths.isNotEmpty)
          DropdownButton<String>(
            value: _selectedMonth,
            items: _availableMonths
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (val) {
              setState(() => _selectedMonth = val);
              _filterHours();
            },
          ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double breakpoint = 750.0;
        final cardOrdinarie = _buildStatCard(
          'Ordinarie',
          totaleOrdinary.toStringAsFixed(2),
          Icons.work_outline,
        );
        final cardStraordinario = _buildStatCard(
          'Straordinario',
          totaleOvertime.toStringAsFixed(2),
          Icons.timer,
        );
        final cardComplessive = _buildStatCard(
          'Complessive',
          (totaleOrdinary + totaleOvertime).toStringAsFixed(2),
          Icons.access_time_filled,
        );
        final cardGuadagni = _buildStatCard(
          'Guadagni (€)',
          totalEarnings.toStringAsFixed(2),
          Icons.euro_symbol,
        );

        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: cardOrdinarie),
                  const SizedBox(width: 16),
                  Expanded(child: cardStraordinario),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: cardComplessive),
                  const SizedBox(width: 16),
                  Expanded(child: cardGuadagni),
                ],
              ),
            ],
          );
        } else {
          return Row(
            children: [
              Expanded(child: cardOrdinarie),
              const SizedBox(width: 16),
              Expanded(child: cardStraordinario),
              const SizedBox(width: 16),
              Expanded(child: cardComplessive),
              const SizedBox(width: 16),
              Expanded(child: cardGuadagni),
            ],
          );
        }
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final dailyHours = _groupedHoursByDay();
    final uniqueDays = dailyHours.keys.toList()
      ..sort(
        (a, b) => DateFormat(
          'dd/MM',
        ).parse(a).compareTo(DateFormat('dd/MM').parse(b)),
      );
    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: uniqueDays.isNotEmpty ? uniqueDays.length.toDouble() - 1 : 0,
          minY: 0,
          maxY: dailyHours.values.isNotEmpty
              ? dailyHours.values.reduce((a, b) => a > b ? a : b) + 2
              : 10,
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  int index = value.toInt();
                  if (index >= 0 && index < uniqueDays.length) {
                    if (uniqueDays.length > 10 && index % 2 != 0) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        uniqueDays[index],
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                uniqueDays.length,
                (i) => FlSpot(i.toDouble(), dailyHours[uniqueDays[i]]!),
              ),
              isCurved: true,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context).colorScheme.primary.withAlpha(50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoursDataTable() {
    String getAziendaName(int aziendaId) {
      final azienda = _aziende.firstWhere(
        (a) => a.id == aziendaId,
        orElse: () => Azienda(name: 'N/A'),
      );
      return azienda.name;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Azienda')),
          DataColumn(label: Text('Data')),
          DataColumn(label: Text('Inizio')),
          DataColumn(label: Text('Fine')),
          DataColumn(label: Text('Pausa')),
          DataColumn(label: Text('Azioni')),
        ],
        rows: _hours.map((h) {
          return DataRow(
            cells: [
              DataCell(Text(getAziendaName(h.aziendaId))),
              DataCell(Text(DateFormat('dd/MM/yyyy').format(h.startTime))),
              DataCell(Text(DateFormat('HH:mm').format(h.startTime))),
              DataCell(Text(DateFormat('HH:mm').format(h.endTime))),
              DataCell(Text('${h.lunchBreak} min')),
              DataCell(
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.orange),
                      onPressed: () => _editHour(h),
                      tooltip: 'Modifica',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteHour(h),
                      tooltip: 'Elimina',
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
