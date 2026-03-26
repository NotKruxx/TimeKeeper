// lib/ui/main_shell.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/add_hours_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/manage_companies_page.dart';
import 'pages/settings_page.dart';
import '../core/firebase/firebase_service.dart';
import 'providers/dashboard_provider.dart';
import 'providers/companies_provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  // IndexedStack keeps page state alive — no const, so providers can rebuild.
  final List<Widget> _pages = const [
    DashboardPage(),
    AddHoursPage(),
    ManageCompaniesPage(),
    SettingsPage(),
  ];

  Future<void> _onItemTapped(int index) async {
    // 1. Flush pending Firebase writes before leaving the current page.
    await FirebaseService.instance.flush();

    // 2. When returning to Dashboard or Companies, reload fresh data.
    if (index == 0) {
      if (mounted) {
        await context.read<DashboardProvider>().load();
      }
    } else if (index == 2) {
      if (mounted) {
        await context.read<CompaniesProvider>().load();
      }
    }

    if (mounted) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Scaffold(
            body: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
            bottomNavigationBar: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.dashboard),  label: 'Dashboard'),
                BottomNavigationBarItem(icon: Icon(Icons.add_circle), label: 'Aggiungi'),
                BottomNavigationBarItem(icon: Icon(Icons.business),   label: 'Aziende'),
                BottomNavigationBarItem(icon: Icon(Icons.settings),   label: 'Impostazioni'),
              ],
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
            ),
          );
        } else {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dashboard_outlined),  selectedIcon: Icon(Icons.dashboard),  label: Text('Dashboard')),
                    NavigationRailDestination(icon: Icon(Icons.add_circle_outline),  selectedIcon: Icon(Icons.add_circle), label: Text('Aggiungi')),
                    NavigationRailDestination(icon: Icon(Icons.business_outlined),   selectedIcon: Icon(Icons.business),   label: Text('Aziende')),
                    NavigationRailDestination(icon: Icon(Icons.settings_outlined),   selectedIcon: Icon(Icons.settings),   label: Text('Impostazioni')),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _pages,
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}