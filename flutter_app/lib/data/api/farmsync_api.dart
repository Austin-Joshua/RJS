import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../models/api_models.dart';

/// Thin wrapper over every `/api/v1` endpoint.
class FarmSyncApi {
  FarmSyncApi(this._client);

  final ApiClient _client;

  // --- health ---
  Future<HealthStatus> healthz() async {
    final r = await _client.get<Map<String, dynamic>>('/healthz');
    return HealthStatus.fromJson(r.data!);
  }

  // --- fields ---
  Future<List<FieldOut>> listFields() async {
    final r = await _client.get<List<dynamic>>('/fields');
    return [for (final e in r.data ?? const []) FieldOut.fromJson(e as Map<String, dynamic>)];
  }

  Future<FieldOut> createField({
    required String name,
    required Map<String, dynamic> boundaryGeojson,
    List<Map<String, dynamic>> plots = const [],
    String? sowingDate,
  }) async {
    final r = await _client.post<Map<String, dynamic>>(
      '/fields',
      data: {
        'name': name,
        'boundary_geojson': boundaryGeojson,
        if (plots.isNotEmpty) 'plots': plots,
        'sowing_date': ?sowingDate,
      },
    );
    return FieldOut.fromJson(r.data!);
  }

  Future<FieldOut> getField(String fieldId) async {
    final r = await _client.get<Map<String, dynamic>>('/fields/$fieldId');
    return FieldOut.fromJson(r.data!);
  }

  Future<FieldOut> updateBoundary(String fieldId, Map<String, dynamic> boundaryGeojson) async {
    final r = await _client.put<Map<String, dynamic>>(
      '/fields/$fieldId/boundary',
      data: {'boundary_geojson': boundaryGeojson},
    );
    return FieldOut.fromJson(r.data!);
  }

  Future<FieldOut> soilOverride(
    String fieldId, {
    required double nKgHa,
    required double pKgHa,
    required double kKgHa,
    required double ph,
    required double ocPct,
    double? ecDsM,
  }) async {
    final r = await _client.post<Map<String, dynamic>>(
      '/fields/$fieldId/soil-override',
      data: {
        'n_kg_ha': nKgHa,
        'p_kg_ha': pKgHa,
        'k_kg_ha': kKgHa,
        'ph': ph,
        'oc_pct': ocPct,
        'ec_ds_m': ?ecDsM,
      },
    );
    return FieldOut.fromJson(r.data!);
  }

  Future<void> deleteField(String fieldId) async {
    await _client.delete<void>('/fields/$fieldId');
  }

  // --- signals ---
  Future<SignalsOut> getSignals(String fieldId) async {
    final r = await _client.get<Map<String, dynamic>>('/fields/$fieldId/signals');
    return SignalsOut.fromJson(r.data!);
  }

  Future<({List<int> bytes, String? geoBounds})> ndviPng(String fieldId) =>
      _client.getBytes('/fields/$fieldId/layers/ndvi.png');

  Future<Map<String, dynamic>> ndviSeries(String fieldId) async {
    final r = await _client.get<Map<String, dynamic>>('/fields/$fieldId/ndvi-series');
    return r.data!;
  }

  Future<Map<String, dynamic>> prices({required String crop, required String district}) async {
    final r = await _client.get<Map<String, dynamic>>(
      '/prices',
      queryParameters: {'crop': crop, 'district': district},
    );
    return r.data!;
  }

  // --- rasters ---
  Future<Map<String, dynamic>> uploadRaster(
    String fieldId, {
    required List<int> bytes,
    required String fileName,
    String kind = 'ndvi',
    int band = 1,
  }) async {
    final form = FormData.fromMap({
      'kind': kind,
      'band': band,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final r = await _client.post<Map<String, dynamic>>('/fields/$fieldId/rasters', data: form);
    return r.data!;
  }

  Future<List<RasterAssetOut>> listRasters(String fieldId) async {
    final r = await _client.get<List<dynamic>>('/fields/$fieldId/rasters');
    return [for (final e in r.data ?? const []) RasterAssetOut.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> deleteRaster(String fieldId, String assetId) async {
    await _client.delete<void>('/fields/$fieldId/rasters/$assetId');
  }

  Future<({List<int> bytes, String? geoBounds})> rasterNdviPng(String fieldId) =>
      _client.getBytes('/fields/$fieldId/layers/raster-ndvi.png');

  Future<({List<int> bytes, String? geoBounds})> orthomosaicPng(String fieldId) =>
      _client.getBytes('/fields/$fieldId/layers/orthomosaic.png');

  Future<({List<int> bytes, String? geoBounds})> demHillshadePng(String fieldId) =>
      _client.getBytes('/fields/$fieldId/layers/dem-hillshade.png');

  /// Fetch any `/api/v1/...` relative path as bytes (auth + X-Geo-Bounds).
  Future<({List<int> bytes, String? geoBounds})> layerBytes(String apiV1RelativePath) {
    var path = apiV1RelativePath;
    if (path.contains('/api/v1')) path = path.split('/api/v1').last;
    if (!path.startsWith('/')) path = '/$path';
    return _client.getBytes(path);
  }

  Future<MapManifestOut> mapManifest(String fieldId) async {
    final r = await _client.get<Map<String, dynamic>>('/fields/$fieldId/map-manifest');
    return MapManifestOut.fromJson(r.data!);
  }

  // --- predict ---
  Future<PredictYieldOut> predictYield({required String fieldId, required List<String> crops}) async {
    final r = await _client.post<Map<String, dynamic>>(
      '/predict/yield',
      data: {'field_id': fieldId, 'crops': crops},
    );
    return PredictYieldOut.fromJson(r.data!);
  }

  // --- plan ---
  Future<PlanOut> createPlan({
    required String fieldId,
    required List<Map<String, dynamic>> plots,
    required List<String> candidateCrops,
    required double waterM3,
    required double budgetRs,
    Map<String, double>? priceOverrides,
  }) async {
    final r = await _client.post<Map<String, dynamic>>(
      '/plan',
      data: {
        'field_id': fieldId,
        'plots': plots,
        'candidate_crops': candidateCrops,
        'constraints': {'water_m3': waterM3, 'budget_rs': budgetRs},
        'price_overrides': ?priceOverrides,
      },
    );
    return PlanOut.fromJson(r.data!);
  }

  Future<AdvisoryOut> getAdvisory(String fieldId) async {
    final r = await _client.get<Map<String, dynamic>>('/fields/$fieldId/advisory');
    return AdvisoryOut.fromJson(r.data!);
  }

  // --- analytics ---
  Future<Map<String, dynamic>> modelMetrics() async {
    final r = await _client.get<Map<String, dynamic>>('/analytics/model-metrics');
    return r.data!;
  }

  Future<Map<String, dynamic>> featureImportance() async {
    final r = await _client.get<Map<String, dynamic>>('/analytics/feature-importance');
    return r.data!;
  }

  Future<Map<String, dynamic>> yieldVsRainfall() async {
    final r = await _client.get<Map<String, dynamic>>('/analytics/yield-vs-rainfall');
    return r.data!;
  }

  Future<Map<String, dynamic>> quantumBenchmark() async {
    final r = await _client.get<Map<String, dynamic>>('/analytics/quantum-benchmark');
    return r.data!;
  }
}
