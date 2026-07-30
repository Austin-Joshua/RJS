import 'package:drift/drift.dart';

/// Cached copy of a farmer's field (backend `FieldResponse`, TRD §8) so the
/// app can list/open fields with zero connectivity.
class Fields extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get areaHa => real()();
  TextColumn get district => text()();
  TextColumn get state => text()();
  TextColumn get sowingDate => text().nullable()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A field's sub-plots (backend `PlotOut`) — what `PlanRequest.plots`
/// allocates crops across.
class Plots extends Table {
  TextColumn get id => text()();
  TextColumn get fieldId => text().references(Fields, #id)();
  TextColumn get label => text()();
  RealColumn get areaHa => real()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One cached QAOA/classical-fallback plan run (backend `PlanResponse`). The
/// three headline numbers are real columns for cheap sorting/display; the
/// nested benchmark/advisory/alternatives objects are kept as their
/// as-received JSON since nothing here needs to query inside them — decoding
/// happens in the repository layer, right where the typed Dart models live.
class CropPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get requestId => text()();
  TextColumn get fieldId => text().references(Fields, #id)();
  TextColumn get solver => text()(); // 'qaoa' | 'classical_fallback'
  TextColumn get dataMode => text()(); // 'live' | 'degraded' | 'demo'
  RealColumn get netValueRs => real()();
  RealColumn get netValueP10Rs => real()();
  RealColumn get netValueP90Rs => real()();
  RealColumn get waterUsedM3 => real()();
  RealColumn get budgetUsedRs => real()();
  TextColumn get benchmarkJson => text()(); // BenchmarkPayload — drives the QAOA convergence graph
  TextColumn get advisoryJson => text()(); // AdvisoryPayload (fertilizer/ph/irrigation/why)
  TextColumn get alternativesJson => text()(); // {"..." : ClassicalAlternative}
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Per-plot crop assignment for a plan (backend `PlanAssignment`), normalized
/// out of CropPlans so the dashboard/map can list "which crop on which plot"
/// without decoding JSON.
class PlanAssignments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId => integer().references(CropPlans, #id)();
  TextColumn get plotId => text()();
  TextColumn get crop => text()();
  RealColumn get yieldTHa => real()();
  RealColumn get p10 => real()();
  RealColumn get p90 => real()();
}

/// Outbound write not yet confirmed by the backend — what
/// [SyncStatusWidget] reads to show "Saved locally" vs "Syncing" vs "Synced"
/// (the offline-first robustness proof). `kind` + `payloadJson` are enough
/// to replay the request once connectivity returns.
enum SyncOpStatus { pending, syncing, synced, failed }

class SyncQueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()(); // e.g. 'plan_request', 'field_create'
  TextColumn get payloadJson => text()();
  IntColumn get status => intEnum<SyncOpStatus>()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
}
