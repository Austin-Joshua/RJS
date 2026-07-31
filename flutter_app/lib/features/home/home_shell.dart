import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo_session.dart';
import '../../core/theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../farms/farm_list_screen.dart';

/// Two tabs: manage farms, and the picture across all of them.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.demoMode = false});

  final bool demoMode;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tabIndex = 0;

  static const _tabs = [
    (title: 'My Farms', icon: Icons.agriculture_outlined, selectedIcon: Icons.agriculture),
    (title: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_tabIndex].title),
        actions: [
          if (widget.demoMode)
            TextButton(
              onPressed: () => ref.read(demoSessionProvider.notifier).end(),
              child: const Text('Leave demo', style: TextStyle(color: Colors.white)),
            )
          else
            const Padding(padding: EdgeInsets.only(right: 8), child: ClerkUserButton()),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [FarmListScreen(), DashboardScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        backgroundColor: AppColors.cream,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.title,
            ),
        ],
      ),
    );
  }
}
