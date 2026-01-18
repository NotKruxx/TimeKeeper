// lib/ui/main_shell.dart

import 'package:flutter/material.dart';
import 'pages/add_hours_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/manage_companies_page.dart';
// import 'pages/scan_page.dart'; // RIMOSSO TEMPORANEAMENTE
import 'pages/settings_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    DashboardPage(),
    // ScanPage(), // RIMOSSO TEMPORANEAMENTE
    AddHoursPage(),
    ManageCompaniesPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Scaffold(
            body: _pages.elementAt(_selectedIndex),
            bottomNavigationBar: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                /* RIMOSSO TEMPORANEAMENTE
                BottomNavigationBarItem(
                  icon: Icon(Icons.qr_code_scanner),
                  label: 'Scansiona',
                ),
                */
                BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle),
                  label: 'Aggiungi',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.business),
                  label: 'Aziende',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Impostazioni',
                ),
              ],
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
            ),
          );
        } else {
          return Scaffold(
            body: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  labelType: NavigationRailLabelType.all,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Dashboard'),
                    ),
                    /* RIMOSSO TEMPORANEAMENTE
                    NavigationRailDestination(
                      icon: Icon(Icons.qr_code_scanner_outlined),
                      selectedIcon: Icon(Icons.qr_code_scanner),
                      label: Text('Scansiona'),
                    ),
                    */
                    NavigationRailDestination(
                      icon: Icon(Icons.add_circle_outline),
                      selectedIcon: Icon(Icons.add_circle),
                      label: Text('Aggiungi'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.business_outlined),
                      selectedIcon: Icon(Icons.business),
                      label: Text('Aziende'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Impostazioni'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: _pages.elementAt(_selectedIndex)),
              ],
            ),
          );
        }
      },
    );
  }
}