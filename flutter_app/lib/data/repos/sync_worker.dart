import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/database/tables.dart';
import '../../core/env.dart';
import 'field_repo.dart';

/// Drains Drift sync queue against the live API.
class SyncWorker {
  SyncWorker(this._ref);

  final Ref _ref;

  Future<void> flush() async {
    if (!Env.isApiConfigured) return;
    final db = _ref.read(appDatabaseProvider);
    final api = _ref.read(farmSyncApiProvider);
    final field = await _ref.read(activeFieldProvider.future);
    final pending = await (db.select(db.syncQueueItems)
          ..where((t) => t.status.isIn([SyncOpStatus.pending.index, SyncOpStatus.failed.index])))
        .get();

    for (final row in pending) {
      await (db.update(db.syncQueueItems)..where((t) => t.id.equals(row.id))).write(
            SyncQueueItemsCompanion(
              status: const Value(SyncOpStatus.syncing),
              lastAttemptAt: Value(DateTime.now()),
            ),
          );
      try {
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        switch (row.kind) {
          case 'soil_card_ocr':
            final fieldId = field?.id ?? payload['field_id'] as String?;
            if (fieldId == null) throw StateError('No field for soil override');
            await api.soilOverride(
              fieldId,
              nKgHa: (payload['n_kg_ha'] as num).toDouble(),
              pKgHa: (payload['p_kg_ha'] as num).toDouble(),
              kKgHa: (payload['k_kg_ha'] as num).toDouble(),
              ph: (payload['ph'] as num).toDouble(),
              ocPct: (payload['oc_pct'] as num).toDouble(),
              ecDsM: (payload['ec_ds_m'] as num?)?.toDouble(),
            );
          case 'plan_request':
            await api.createPlan(
              fieldId: payload['field_id'] as String,
              plots: List<Map<String, dynamic>>.from(payload['plots'] as List),
              candidateCrops: List<String>.from(payload['candidate_crops'] as List),
              waterM3: (payload['water_m3'] as num).toDouble(),
              budgetRs: (payload['budget_rs'] as num).toDouble(),
            );
          default:
            // Unknown kind — leave pending for a future worker.
            await (db.update(db.syncQueueItems)..where((t) => t.id.equals(row.id))).write(
                  const SyncQueueItemsCompanion(status: Value(SyncOpStatus.pending)),
                );
            continue;
        }
        await (db.update(db.syncQueueItems)..where((t) => t.id.equals(row.id))).write(
              const SyncQueueItemsCompanion(status: Value(SyncOpStatus.synced), errorMessage: Value(null)),
            );
      } catch (e) {
        await (db.update(db.syncQueueItems)..where((t) => t.id.equals(row.id))).write(
              SyncQueueItemsCompanion(
                status: const Value(SyncOpStatus.failed),
                errorMessage: Value(e.toString()),
              ),
            );
      }
    }
  }
}

final syncWorkerProvider = Provider<SyncWorker>((ref) => SyncWorker(ref));
