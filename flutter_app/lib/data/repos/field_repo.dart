import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/env.dart';
import '../api/farmsync_api.dart';
import '../models/api_models.dart';

final farmSyncApiProvider = Provider<FarmSyncApi>((ref) => FarmSyncApi(ref.watch(apiClientProvider)));

class FieldRepository {
  FieldRepository(this._api, this._db);

  final FarmSyncApi _api;
  final AppDatabase _db;

  Future<void> _cacheField(FieldOut f) async {
    await _db.into(_db.fields).insertOnConflictUpdate(
          FieldsCompanion.insert(
            id: f.id,
            name: f.name,
            lat: f.lat,
            lon: f.lon,
            areaHa: f.areaHa,
            district: f.district,
            state: f.state,
            sowingDate: Value(f.sowingDate),
          ),
        );
    await (_db.delete(_db.plots)..where((t) => t.fieldId.equals(f.id))).go();
    for (final p in f.plots) {
      await _db.into(_db.plots).insertOnConflictUpdate(
            PlotsCompanion.insert(id: p.id, fieldId: f.id, label: p.label, areaHa: p.areaHa),
          );
    }
  }

  Future<List<FieldOut>> listCached() async {
    final rows = await _db.select(_db.fields).get();
    final out = <FieldOut>[];
    for (final f in rows) {
      final plots = await (_db.select(_db.plots)..where((t) => t.fieldId.equals(f.id))).get();
      out.add(
        FieldOut(
          id: f.id,
          name: f.name,
          lat: f.lat,
          lon: f.lon,
          areaHa: f.areaHa,
          district: f.district,
          state: f.state,
          sowingDate: f.sowingDate,
          plots: [for (final p in plots) PlotOut(id: p.id, label: p.label, areaHa: p.areaHa)],
        ),
      );
    }
    return out;
  }

  /// Sync from API when configured; fall back to Drift cache.
  Future<List<FieldOut>> refresh() async {
    if (!Env.isApiConfigured) return listCached();
    try {
      final live = await _api.listFields();
      for (final f in live) {
        await _cacheField(f);
      }
      return live;
    } catch (_) {
      return listCached();
    }
  }

  /// Ensure at least one field exists for demo-farmer: list, else create from bundled GeoJSON.
  Future<FieldOut> ensureDemoField() async {
    final existing = await refresh();
    if (existing.isNotEmpty) return existing.first;

    if (!Env.isApiConfigured) {
      throw StateError('API_BASE_URL not set and no cached fields');
    }

    final raw = jsonDecode(await rootBundle.loadString('assets/demo/kallapuram_boundary.geojson')) as Map<String, dynamic>;
    final geom = Map<String, dynamic>.from(raw['geometry'] as Map);
    final props = raw['properties'] as Map<String, dynamic>? ?? {};
    final name = (props['name'] as String?) ?? 'Kallapuram field';

    final created = await _api.createField(
      name: name,
      boundaryGeojson: geom,
      plots: const [
        {'label': 'Plot 1', 'area_ha': 0.5},
        {'label': 'Plot 2', 'area_ha': 0.5},
        {'label': 'Plot 3', 'area_ha': 0.5},
      ],
    );
    await _cacheField(created);
    return created;
  }
}

final fieldRepositoryProvider = Provider<FieldRepository>(
  (ref) => FieldRepository(ref.watch(farmSyncApiProvider), ref.watch(appDatabaseProvider)),
);

/// Active field for Map / Dashboard / Soil. Bootstraps demo field when API is up.
final activeFieldProvider = FutureProvider<FieldOut?>((ref) async {
  if (!Env.isApiConfigured) return null;
  final repo = ref.watch(fieldRepositoryProvider);
  try {
    return await repo.ensureDemoField();
  } catch (_) {
    final cached = await repo.listCached();
    return cached.isEmpty ? null : cached.first;
  }
});
