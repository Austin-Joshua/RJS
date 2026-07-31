import 'dart:ui';

import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo_session.dart';
import '../../core/widgets/glass.dart';
import '../dashboard/dashboard_screen.dart';
import '../farms/farm_list_screen.dart';
import '../quantum/quantum_lab_providers.dart';
import '../quantum/quantum_lab_screen.dart';

/// Three tabs: farms, farm report, and the quantum survival / comparison lab.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.demoMode = false});

  final bool demoMode;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = [
    (title: 'My Farms', icon: Icons.agriculture_outlined, selectedIcon: Icons.agriculture),
    (title: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
    (title: 'Quantum', icon: Icons.memory_outlined, selectedIcon: Icons.memory),
  ];

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(homeTabIndexProvider).clamp(0, _tabs.length - 1);

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_tabs[tabIndex].title),
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
          index: tabIndex,
          children: const [FarmListScreen(), DashboardScreen(), QuantumLabScreen()],
        ),
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: NavigationBar(
              selectedIndex: tabIndex,
              onDestinationSelected: (index) => ref.read(homeTabIndexProvider.notifier).go(index),
              backgroundColor: Colors.white.withValues(alpha: 0.55),
              destinations: [
                for (final tab in _tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.title,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
