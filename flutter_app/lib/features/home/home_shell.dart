import 'dart:ui';

import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/demo_session.dart';
import '../../core/widgets/glass.dart';
import '../dashboard/dashboard_screen.dart';
import '../farms/farm_list_screen.dart';
import '../quantum/quantum_lab_providers.dart';
import '../quantum/quantum_lab_screen.dart';

/// FarmSync shell — farms, report, quantum lab.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.demoMode = false});

  final bool demoMode;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = [
    (title: 'Farms', icon: Icons.agriculture_outlined, selectedIcon: Icons.agriculture),
    (title: 'Report', icon: Icons.insights_outlined, selectedIcon: Icons.insights),
    (title: 'Planner', icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome),
  ];

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(homeTabIndexProvider).clamp(0, _tabs.length - 1);
    final tab = _tabs[tabIndex];

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.grass_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    AppBrand.name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70),
                  ),
                  Text(tab.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          actions: [
            if (widget.demoMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: () => ref.read(demoSessionProvider.notifier).end(),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Leave demo'),
                ),
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
              height: 64,
              selectedIndex: tabIndex,
              onDestinationSelected: (index) => ref.read(homeTabIndexProvider.notifier).go(index),
              backgroundColor: Colors.white.withValues(alpha: 0.62),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.selectedIcon),
                    label: t.title,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
