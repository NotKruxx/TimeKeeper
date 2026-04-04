// lib/ui/pages/dashboard_page.dart
//
// Pure UI — zero business logic, zero DB calls.
// Tutti i dati arrivano da DashboardProvider via context.watch / context.read.

import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/hours_worked_model.dart';
import '../../data/models/azienda_model.dart';
import '../providers/data_cache_provider.dart';
import '../../ui/providers/dashboard_provider.dart';
import 'edit_hours_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _reloadData();
    }
  }

  // Helper method per ricaricare i dati delegando al DataCacheProvider
  Future<void> _reloadData() async {
    // Sostituisci 'loadData' con il metodo corretto del tuo DataCacheProvider
    // (es. fetchAll(), init(), load(), ecc.)
    // await context.read<DataCacheProvider>().loadData(); 
  }

  // ── Export CSV ───────────────────────────────────────────────
  Future<void> _exportCsv(DashboardProvider p) async {
    final hours = p.filteredHours;
    if (hours.isEmpty) {
      _snack('Nessun dato da esportare per il filtro selezionato.');
      return;
    }

    final rows = <List<dynamic>>[
      ['Azienda', 'Data', 'Inizio', 'Fine', 'Pausa (min)', 'Ore Ordinarie', 'Ore Straordinario', 'Note'],
      ...hours.map((h) {
        final az = p.aziendaFor(h.aziendaUuid);
        return [
          az?.name ?? 'N/A',
          DateFormat('dd/MM/yyyy').format(h.startTime.toLocal()),
          DateFormat('HH:mm').format(h.startTime.toLocal()),
          DateFormat('HH:mm').format(h.endTime.toLocal()),
          h.lunchBreak,
          p.ordinary(h).toStringAsFixed(2),
          p.overtime(h).toStringAsFixed(2),
          h.notes ?? '',
        ];
      }),
    ];

    final csvString = const ListToCsvConverter().convert(rows);

    if (kIsWeb) {
      _snack('CSV generato — usa la condivisione nativa dal browser.');
      return;
    }

    final bytes = Uint8List.fromList(utf8.encode(csvString));
    final file  = XFile.fromData(
      bytes,
      name:     'report_${p.selectedMonth ?? 'all'}.csv',
      mimeType: 'text/csv',
    );

    await Share.shareXFiles([file], text: 'Report ore lavorate');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Edit / Delete ─────────────────────────────────────────────
  Future<void> _delete(DashboardProvider p, HoursWorkedModel h) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: const Text('Vuoi davvero eliminare questo turno?'),
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
    if (confirmed == true && mounted) {
      await context.read<DataCacheProvider>().deleteHour(h.uuid);
    }
  }

  void _edit(HoursWorkedModel h) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditHoursPage(hourToEdit: h)),
    ).then((_) {
      if (mounted) _reloadData();
    });
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = context.watch<DashboardProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Esporta CSV',
            onPressed: () => _exportCsv(p),
          ),
        ],
      ),
      // Usiamo isLoading al posto di isReallyLoading
      body: p.isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reloadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Filters(provider: p),
                    const SizedBox(height: 24),
                    if (p.filteredHours.isEmpty)
                      const SizedBox(
                        height: 200,
                        child: Center(
                          child: Text(
                            'Nessun dato per il periodo selezionato.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else ...[
                      _StatsRow(provider: p),
                      const SizedBox(height: 24),
                      _HoursChart(provider: p),
                      const SizedBox(height: 24),
                      Text('Dettaglio Ore', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      _HoursTable(
                        provider: p,
                        onEdit: _edit,
                        onDelete: (h) => _delete(p, h),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  const _Filters({required this.provider});
  final DashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider.aziende.isEmpty && provider.availableMonths.isEmpty) {
      return const Text(
        "Nessun dato. Aggiungi un'azienda e delle ore per iniziare.",
        style: TextStyle(color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        if (provider.aziende.isNotEmpty)
          DropdownButton<AziendaModel>(
            value: provider.aziende.contains(provider.selectedAzienda) ? provider.selectedAzienda : null,
            items: provider.aziende
                .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                .toList(),
            onChanged: provider.selectAzienda,
            hint: const Text('Seleziona Azienda'),
          ),
        if (provider.availableMonths.isNotEmpty)
          DropdownButton<String>(
            value: provider.availableMonths.contains(provider.selectedMonth) ? provider.selectedMonth : null,
            items: provider.availableMonths
                .map((m) => DropdownMenuItem(value: m, child: Text(_formatMonthKey(m))))
                .toList(),
            onChanged: provider.selectMonth,
            hint: const Text('Seleziona Mese'),
          ),
      ],
    );
  }

  String _formatMonthKey(String key) {
    try {
      final parts = key.split('-');
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('MMMM yyyy', 'it_IT').format(dt);
    } catch (_) {
      return key;
    }
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.provider});
  final DashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(label: 'Ordinarie',     value: provider.totalOrdinary.toStringAsFixed(2),                           icon: Icons.work_outline),
      _StatCard(label: 'Straordinario', value: provider.totalOvertime.toStringAsFixed(2),                           icon: Icons.timer),
      _StatCard(label: 'Complessive',   value: (provider.totalOrdinary + provider.totalOvertime).toStringAsFixed(2), icon: Icons.access_time_filled),
      _StatCard(label: 'Guadagni (€)',  value: provider.totalEarnings.toStringAsFixed(2),                           icon: Icons.euro_symbol),
    ];

    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth < 750) {
        return Column(
          children: [
            Row(children: [Expanded(child: cards[0]), const SizedBox(width: 16), Expanded(child: cards[1])]),
            const SizedBox(height: 16),
            Row(children: [Expanded(child: cards[2]), const SizedBox(width: 16), Expanded(child: cards[3])]),
          ],
        );
      }
      return Row(
        children: cards
            .expand((c) => [Expanded(child: c), const SizedBox(width: 16)])
            .toList()
          ..removeLast(),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }
}

class _HoursChart extends StatelessWidget {
  const _HoursChart({required this.provider});
  final DashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    final data  = provider.hoursByDay;
    final days  = data.keys.toList()..sort();
    if (days.isEmpty) return const SizedBox();

    final spots   = List.generate(days.length, (i) => FlSpot(i.toDouble(), data[days[i]]!));
    final maxY    = (data.values.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: days.length > 1 ? days.length.toDouble() - 1 : 1,
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(show: true),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox();
                  if (days.length > 10 && i.isOdd)  return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(days[i], style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: primary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: primary.withAlpha(50)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoursTable extends StatelessWidget {
  const _HoursTable({
    required this.provider,
    required this.onEdit,
    required this.onDelete,
  });
  final DashboardProvider provider;
  final void Function(HoursWorkedModel) onEdit;
  final void Function(HoursWorkedModel) onDelete;

  @override
  Widget build(BuildContext context) {
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
        rows: provider.filteredHours.map((h) => DataRow(cells: [
          DataCell(Text(provider.aziendaName(h.aziendaUuid))),
          DataCell(Text(DateFormat('dd/MM/yyyy').format(h.startTime.toLocal()))),
          DataCell(Text(DateFormat('HH:mm').format(h.startTime.toLocal()))),
          DataCell(Text(DateFormat('HH:mm').format(h.endTime.toLocal()))),
          DataCell(Text('${h.lunchBreak} min')),
          DataCell(Row(children: [
            IconButton(icon: const Icon(Icons.edit, color: Colors.orange), onPressed: () => onEdit(h), tooltip: 'Modifica'),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => onDelete(h), tooltip: 'Elimina'),
          ])),
        ])).toList(),
      ),
    );
  }
} 