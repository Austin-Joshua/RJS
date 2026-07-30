import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Fields, Plots, CropPlans, PlanAssignments, SyncQueueItems])
class AppDatabase extends _$AppDatabase {
  // Constructor takes an optional executor so tests can pass an in-memory
  // database instead of touching disk.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() => driftDatabase(name: 'farmsync');
}
