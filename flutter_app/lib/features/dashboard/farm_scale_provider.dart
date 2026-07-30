import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FarmScale { singleFarm, villageCoop }

class FarmScaleNotifier extends Notifier<FarmScale> {
  @override
  FarmScale build() => FarmScale.singleFarm;

  void set(FarmScale scale) => state = scale;
}

final farmScaleProvider = NotifierProvider<FarmScaleNotifier, FarmScale>(FarmScaleNotifier.new);

/// True while village co-op mode is "routing" to the QAOA simulator (pitch demo).
final villageRoutingProvider = NotifierProvider<_BoolNotifier, bool>(_BoolNotifier.new);

class _BoolNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
