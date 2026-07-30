import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/database/tables.dart';
import '../../core/env.dart';
import '../../features/dashboard/constraints_provider.dart';
import '../api/farmsync_api.dart';
import '../models/api_models.dart';
import 'field_repo.dart';

class PlanRepository {
  PlanRepository(this._api, this._db);

  final FarmSyncApi _api;
  final AppDatabase _db;

  Future<int> _persist(PlanOut plan, String fieldId) async {
    final planId = await _db.into(_db.cropPlans).insert(
          CropPlansCompanion.insert(
            requestId: plan.requestId,
            fieldId: fieldId,
            solver: plan.plan.solver,
            dataMode: plan.dataMode,
            netValueRs: plan.plan.netValueRs,
            netValueP10Rs: plan.plan.netValueP10Rs,
            netValueP90Rs: plan.plan.netValueP90Rs,
            waterUsedM3: plan.plan.waterUsedM3,
            budgetUsedRs: plan.plan.budgetUsedRs,
            benchmarkJson: jsonEncode(plan.benchmark.raw ?? {}),
            advisoryJson: jsonEncode({
              'fertilizer': plan.advisory.fertilizer,
              'ph': plan.advisory.ph,
              'irrigation': plan.advisory.irrigation,
              'why': plan.advisory.why,
            }),
            alternativesJson: jsonEncode(plan.alternatives),
          ),
        );
    for (final a in plan.plan.assignments) {
      await _db.into(_db.planAssignments).insert(
            PlanAssignmentsCompanion.insert(
              planId: planId,
              plotId: a.plotId,
              crop: a.crop,
              yieldTHa: a.yieldTHa,
              p10: a.p10,
              p90: a.p90,
            ),
          );
    }
    return planId;
  }

  Future<PlanOut?> latestCached(String fieldId) async {
    final row = await (_db.select(_db.cropPlans)
          ..where((t) => t.fieldId.equals(fieldId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final assignments = await (_db.select(_db.planAssignments)..where((t) => t.planId.equals(row.id))).get();
    final advisory = jsonDecode(row.advisoryJson) as Map<String, dynamic>;
    final benchmark = jsonDecode(row.benchmarkJson) as Map<String, dynamic>;
    final alternatives = jsonDecode(row.alternativesJson) as Map<String, dynamic>;
    return PlanOut(
      requestId: row.requestId,
      plan: PlanCoreOut(
        solver: row.solver,
        assignments: [
          for (final a in assignments)
            PlanAssignmentOut(
              plotId: a.plotId,
              crop: a.crop,
              yieldTHa: a.yieldTHa,
              p10: a.p10,
              p90: a.p90,
            ),
        ],
        netValueRs: row.netValueRs,
        netValueP10Rs: row.netValueP10Rs,
        netValueP90Rs: row.netValueP90Rs,
        waterUsedM3: row.waterUsedM3,
        budgetUsedRs: row.budgetUsedRs,
      ),
      alternatives: alternatives,
      benchmark: BenchmarkOut.fromJson(benchmark),
      advisory: AdvisoryOut.fromJson(advisory),
      dataMode: row.dataMode,
      timings: const {},
      raw: const {},
    );
  }

  Future<PlanOut> generate({
    required FieldOut field,
    required PlanConstraints constraints,
    List<String> crops = const ['paddy', 'maize', 'groundnut'],
  }) async {
    if (!Env.isApiConfigured) {
      final cached = await latestCached(field.id);
      if (cached != null) return cached;
      throw StateError('API_BASE_URL not set');
    }

    final plots = field.plots.isEmpty
        ? [
            {'plot_id': 'p1', 'area_ha': field.areaHa > 0 ? field.areaHa : 1.0},
          ]
        : [
            for (final p in field.plots) {'plot_id': p.id, 'area_ha': p.areaHa},
          ];

    try {
      final plan = await _api.createPlan(
        fieldId: field.id,
        plots: plots,
        candidateCrops: crops,
        waterM3: constraints.waterM3,
        budgetRs: constraints.budgetRs,
      );
      await _persist(plan, field.id);
      return plan;
    } catch (e) {
      await _db.into(_db.syncQueueItems).insert(
            SyncQueueItemsCompanion.insert(
              kind: 'plan_request',
              payloadJson: jsonEncode({
                'field_id': field.id,
                'plots': plots,
                'candidate_crops': crops,
                'water_m3': constraints.waterM3,
                'budget_rs': constraints.budgetRs,
              }),
              status: SyncOpStatus.pending,
            ),
          );
      final cached = await latestCached(field.id);
      if (cached != null) return cached;
      rethrow;
    }
  }
}

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => PlanRepository(ref.watch(farmSyncApiProvider), ref.watch(appDatabaseProvider)),
);

final latestPlanProvider = FutureProvider.autoDispose<PlanOut?>((ref) async {
  final field = await ref.watch(activeFieldProvider.future);
  if (field == null) return null;
  return ref.watch(planRepositoryProvider).latestCached(field.id);
});
