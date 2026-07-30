import 'package:drift/native.dart';
import 'package:flutter_app/core/database/database.dart';
import 'package:flutter_app/core/database/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// Self-check for the offline-cache schema: round-trips one field, one QAOA
/// plan, its plot assignment, and one sync-queue entry through an in-memory
/// database, mirroring the shapes the repository layer will persist.
void main() {
  test('AppDatabase persists a plan and its assignments end to end', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.fields).insert(
      FieldsCompanion.insert(
        id: 'field-1',
        name: 'North Plot',
        lat: 11.0,
        lon: 78.0,
        areaHa: 2.5,
        district: 'Coimbatore',
        state: 'Tamil Nadu',
      ),
    );

    final planId = await db.into(db.cropPlans).insert(
      CropPlansCompanion.insert(
        requestId: 'req-1',
        fieldId: 'field-1',
        solver: 'qaoa',
        dataMode: 'live',
        netValueRs: 45000,
        netValueP10Rs: 38000,
        netValueP90Rs: 52000,
        waterUsedM3: 1200,
        budgetUsedRs: 15000,
        benchmarkJson: '{}',
        advisoryJson: '{}',
        alternativesJson: '{}',
      ),
    );

    await db.into(db.planAssignments).insert(
      PlanAssignmentsCompanion.insert(
        planId: planId,
        plotId: 'plot-1',
        crop: 'paddy',
        yieldTHa: 4.2,
        p10: 3.5,
        p90: 4.8,
      ),
    );

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        kind: 'plan_request',
        payloadJson: '{"field_id":"field-1"}',
        status: SyncOpStatus.pending,
      ),
    );

    final storedPlans = await db.select(db.cropPlans).get();
    final storedAssignments = await db.select(db.planAssignments).get();
    final storedQueue = await db.select(db.syncQueueItems).get();

    expect(storedPlans, hasLength(1));
    expect(storedPlans.single.solver, 'qaoa');
    expect(storedAssignments, hasLength(1));
    expect(storedAssignments.single.planId, planId);
    expect(storedQueue, hasLength(1));
    expect(storedQueue.single.status, SyncOpStatus.pending);
  });
}
