import 'package:flutter_app/core/sync/sync_status_provider.dart';
import 'package:flutter_app/core/widgets/sync_status_widget.dart';
import 'package:flutter_app/features/dashboard/constraints_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlanConstraints maps water % to m³', () {
    const c = PlanConstraints(waterPct: 50, budgetRs: 10000);
    expect(c.waterM3, PlanConstraints.maxWaterM3 * 0.5);
  });

  test('planConstraintsProvider updates from sliders', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(planConstraintsProvider.notifier).setWaterPct(40);
    container.read(planConstraintsProvider.notifier).setBudgetRs(50000);

    final state = container.read(planConstraintsProvider);
    expect(state.waterPct, 40);
    expect(state.budgetRs, 50000);
  });

  test('syncStateFromRows prefers syncing over pending', () {
    expect(syncStateFromRows(const []), SyncState.savedLocally);
  });
}
