import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/sync_status_widget.dart';
import '../auth/demo_session.dart';
import '../dashboard/dashboard_screen.dart';
import '../map/map_screen.dart';
import '../soil_scanner/soil_scanner_screen.dart';

/// Bottom nav shell + persistent [SyncStatusWidget] in the AppBar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tabIndex = 0;

  static const _tabs = [
    (title: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, screen: DashboardScreen()),
    (title: 'Map', icon: Icons.map_outlined, selectedIcon: Icons.map, screen: MapScreen()),
    (title: 'Soil Scan', icon: Icons.document_scanner_outlined, selectedIcon: Icons.document_scanner, screen: SoilScannerScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(demoSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(demo ? '${_tabs[_tabIndex].title} · Demo' : _tabs[_tabIndex].title),
        actions: [
          const SyncStatusWidget(),
          if (demo)
            TextButton(
              onPressed: () => ref.read(demoSessionProvider.notifier).exit(),
              child: const Text('Exit demo', style: TextStyle(color: Colors.white)),
            )
          else
            const Padding(padding: EdgeInsets.only(right: 8), child: ClerkUserButton()),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [for (final tab in _tabs) tab.screen],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.icon), selectedIcon: Icon(tab.selectedIcon), label: tab.title),
        ],
        backgroundColor: AppColors.cream,
      ),
    );
  }
}
