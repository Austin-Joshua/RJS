import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-nav tab index for [HomeShell] — farm detail can jump to Quantum Lab.
class HomeTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void go(int index) => state = index;
}

final homeTabIndexProvider = NotifierProvider<HomeTabIndex, int>(HomeTabIndex.new);

/// Farm pre-selected when opening the Quantum Lab from a farm detail screen.
class QuantumLabFarmId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? farmId) => state = farmId;
}

final quantumLabFarmIdProvider =
    NotifierProvider<QuantumLabFarmId, String?>(QuantumLabFarmId.new);
