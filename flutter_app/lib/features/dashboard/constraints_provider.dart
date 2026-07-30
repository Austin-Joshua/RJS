import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plan constraints driven by the dashboard sliders. Absolute water is derived
/// from [waterPct] against a fixed farm max (later: field-level capacity).
class PlanConstraints {
  const PlanConstraints({this.waterPct = 70, this.budgetRs = 25000});

  final double waterPct; // 0–100
  final double budgetRs; // INR

  static const maxWaterM3 = 5000.0;

  double get waterM3 => maxWaterM3 * (waterPct / 100);

  PlanConstraints copyWith({double? waterPct, double? budgetRs}) => PlanConstraints(
        waterPct: waterPct ?? this.waterPct,
        budgetRs: budgetRs ?? this.budgetRs,
      );
}

class PlanConstraintsNotifier extends Notifier<PlanConstraints> {
  @override
  PlanConstraints build() => const PlanConstraints();

  void setWaterPct(double value) => state = state.copyWith(waterPct: value.clamp(0, 100));

  void setBudgetRs(double value) => state = state.copyWith(budgetRs: value.clamp(0, 100000));
}

final planConstraintsProvider =
    NotifierProvider<PlanConstraintsNotifier, PlanConstraints>(PlanConstraintsNotifier.new);
