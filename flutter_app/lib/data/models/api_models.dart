/// Typed models matching backend/app/schemas/{requests,responses}.py
library;

class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.earthEngineInitialized,
    required this.modelLoaded,
    required this.modelVersion,
    required this.authConfigured,
    this.devLoginEnabled = false,
  });

  final String status;
  final bool earthEngineInitialized;
  final bool modelLoaded;
  final String modelVersion;
  /// Whether the server has a Clerk verification key. Without it every data
  /// route 401s, so this is the first thing to check on a bad deploy.
  final bool authConfigured;
  final bool devLoginEnabled;

  factory HealthStatus.fromJson(Map<String, dynamic> j) => HealthStatus(
        status: j['status'] as String? ?? 'ok',
        earthEngineInitialized: j['earth_engine_initialized'] as bool? ?? false,
        modelLoaded: j['model_loaded'] as bool? ?? false,
        modelVersion: j['model_version'] as String? ?? 'v1',
        authConfigured: j['auth_configured'] as bool? ?? false,
        devLoginEnabled: j['dev_login_enabled'] as bool? ?? false,
      );
}

class PlotOut {
  const PlotOut({required this.id, required this.label, required this.areaHa});

  final String id;
  final String label;
  final double areaHa;

  factory PlotOut.fromJson(Map<String, dynamic> j) => PlotOut(
        id: j['id'] as String,
        label: j['label'] as String,
        areaHa: (j['area_ha'] as num).toDouble(),
      );
}

class FieldOut {
  const FieldOut({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.areaHa,
    required this.district,
    required this.state,
    this.sowingDate,
    required this.plots,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double areaHa;
  final String district;
  final String state;
  final String? sowingDate;
  final List<PlotOut> plots;

  factory FieldOut.fromJson(Map<String, dynamic> j) {
    final c = j['centroid'] as Map<String, dynamic>? ?? const {};
    return FieldOut(
      id: j['id'] as String,
      name: j['name'] as String,
      lat: (c['lat'] as num?)?.toDouble() ?? 0,
      lon: (c['lon'] as num?)?.toDouble() ?? 0,
      areaHa: (j['area_ha'] as num).toDouble(),
      district: j['district'] as String? ?? '',
      state: j['state'] as String? ?? '',
      sowingDate: j['sowing_date'] as String?,
      plots: [
        for (final p in (j['plots'] as List<dynamic>? ?? const [])) PlotOut.fromJson(p as Map<String, dynamic>),
      ],
    );
  }
}

class PlanAssignmentOut {
  const PlanAssignmentOut({
    required this.plotId,
    required this.crop,
    required this.yieldTHa,
    required this.p10,
    required this.p90,
  });

  final String plotId;
  final String crop;
  final double yieldTHa;
  final double p10;
  final double p90;

  factory PlanAssignmentOut.fromJson(Map<String, dynamic> j) => PlanAssignmentOut(
        plotId: j['plot_id'] as String,
        crop: j['crop'] as String,
        yieldTHa: (j['yield_t_ha'] as num).toDouble(),
        p10: (j['p10'] as num).toDouble(),
        p90: (j['p90'] as num).toDouble(),
      );
}

/// Profit distribution of a plan across correlated yield scenarios.
///
/// Reported by the backend, not optimised: CVaR is not quadratic in the
/// decision variables, so the QUBO encodes a mean-variance surrogate instead.
class PlanRiskOut {
  const PlanRiskOut({
    required this.expectedRs,
    required this.stdRs,
    required this.cvarRs,
    required this.cvarBeta,
    this.worstCaseRs,
    this.bestCaseRs,
    this.nScenarios,
  });

  final double expectedRs;
  final double stdRs;
  final double cvarRs;
  final double cvarBeta;
  final double? worstCaseRs;
  final double? bestCaseRs;
  final int? nScenarios;

  factory PlanRiskOut.fromJson(Map<String, dynamic> j) => PlanRiskOut(
        expectedRs: (j['expected_rs'] as num?)?.toDouble() ?? 0,
        stdRs: (j['std_rs'] as num?)?.toDouble() ?? 0,
        cvarRs: (j['cvar_rs'] as num?)?.toDouble() ?? 0,
        cvarBeta: (j['cvar_beta'] as num?)?.toDouble() ?? 0.2,
        worstCaseRs: (j['worst_case_rs'] as num?)?.toDouble(),
        bestCaseRs: (j['best_case_rs'] as num?)?.toDouble(),
        nScenarios: (j['n_scenarios'] as num?)?.toInt(),
      );
}

class PlanDiversificationOut {
  const PlanDiversificationOut({
    required this.distinctCrops,
    required this.nPlots,
    required this.cropMix,
  });

  final int distinctCrops;
  final int nPlots;
  final Map<String, int> cropMix;

  factory PlanDiversificationOut.fromJson(Map<String, dynamic> j) => PlanDiversificationOut(
        distinctCrops: (j['distinct_crops'] as num?)?.toInt() ?? 0,
        nPlots: (j['n_plots'] as num?)?.toInt() ?? 0,
        cropMix: {
          for (final e in (j['crop_mix'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: (e.value as num).toInt(),
        },
      );
}

class PlanCoreOut {
  const PlanCoreOut({
    required this.solver,
    required this.assignments,
    required this.netValueRs,
    required this.netValueP10Rs,
    required this.netValueP90Rs,
    required this.waterUsedM3,
    required this.budgetUsedRs,
    this.certaintyEquivalentRs,
    this.riskAdjustedValueRs,
    this.risk,
    this.diversification,
  });

  final String solver;
  final List<PlanAssignmentOut> assignments;
  final double netValueRs;
  final double netValueP10Rs;
  final double netValueP90Rs;
  final double waterUsedM3;
  final double budgetUsedRs;

  /// Expected rupees minus κ standard deviations — what the plan is worth at
  /// the farmer's chosen risk appetite. This is the money figure for the UI.
  final double? certaintyEquivalentRs;

  /// Raw mean-minus-κ·variance score the solver ranked by. Quadratic (so it
  /// fits a QUBO) but not in meaningful rupees — quantum panel only.
  final double? riskAdjustedValueRs;
  final PlanRiskOut? risk;
  final PlanDiversificationOut? diversification;

  factory PlanCoreOut.fromJson(Map<String, dynamic> j) => PlanCoreOut(
        solver: j['solver'] as String,
        assignments: [
          for (final a in (j['assignments'] as List<dynamic>? ?? const []))
            PlanAssignmentOut.fromJson(a as Map<String, dynamic>),
        ],
        netValueRs: (j['net_value_rs'] as num).toDouble(),
        netValueP10Rs: (j['net_value_p10_rs'] as num).toDouble(),
        netValueP90Rs: (j['net_value_p90_rs'] as num).toDouble(),
        waterUsedM3: (j['water_used_m3'] as num).toDouble(),
        budgetUsedRs: (j['budget_used_rs'] as num).toDouble(),
        certaintyEquivalentRs: (j['certainty_equivalent_rs'] as num?)?.toDouble(),
        riskAdjustedValueRs: (j['risk_adjusted_value_rs'] as num?)?.toDouble(),
        risk: j['risk'] == null ? null : PlanRiskOut.fromJson(j['risk'] as Map<String, dynamic>),
        diversification: j['diversification'] == null
            ? null
            : PlanDiversificationOut.fromJson(j['diversification'] as Map<String, dynamic>),
      );
}

/// One point of the real COBYLA trace: CVaR energy at a given INTERP depth.
class ConvergencePoint {
  const ConvergencePoint({required this.layer, required this.iteration, required this.cvarEnergy});

  final int layer;
  final int iteration;
  final double cvarEnergy;

  factory ConvergencePoint.fromJson(Map<String, dynamic> j) => ConvergencePoint(
        layer: (j['layer'] as num?)?.toInt() ?? 1,
        iteration: (j['iteration'] as num?)?.toInt() ?? 0,
        cvarEnergy: (j['cvar_energy'] as num?)?.toDouble() ?? 0,
      );
}

/// The previous-generation transverse-field QAOA, run on the same instance.
/// Shipped in every response so the improvement is a measurement on screen,
/// not a claim in a slide.
class BaselineQaoaOut {
  const BaselineQaoaOut({
    required this.nQubits,
    required this.slackQubits,
    this.feasibleRate,
    this.upliftVsUniform,
    this.upliftVsFeasibleUniform,
    required this.tS,
  });

  final int nQubits;
  final int slackQubits;
  final double? feasibleRate;
  final double? upliftVsUniform;
  final double? upliftVsFeasibleUniform;
  final double tS;

  factory BaselineQaoaOut.fromJson(Map<String, dynamic> j) => BaselineQaoaOut(
        nQubits: (j['n_qubits'] as num?)?.toInt() ?? 0,
        slackQubits: (j['slack_qubits'] as num?)?.toInt() ?? 0,
        feasibleRate: (j['feasible_rate'] as num?)?.toDouble(),
        upliftVsUniform: (j['uplift_vs_uniform'] as num?)?.toDouble(),
        upliftVsFeasibleUniform: (j['uplift_vs_feasible_uniform'] as num?)?.toDouble(),
        tS: (j['t_s'] as num?)?.toDouble() ?? 0,
      );
}

class BenchmarkOut {
  const BenchmarkOut({
    required this.nQubits,
    required this.encoding,
    required this.qaoaLayers,
    required this.quboTerms,
    this.qaoaEnergy,
    required this.classicalOptimum,
    this.approximationRatio,
    required this.matchedOptimum,
    this.pOptimum,
    this.upliftVsUniform,
    this.upliftVsFeasibleUniform,
    this.feasibleRate,
    this.simplexRate,
    required this.tQaoaS,
    required this.tClassicalS,
    required this.claim,
    this.solver = 'sparq',
    this.timedOut = false,
    this.convergence = const [],
    this.warmStart = const {},
    this.riskKappa,
    this.riskScenarios,
    this.planStdRs,
    this.riskNeutralStdRs,
    this.profitHistogram = const [],
    this.baseline,
    this.raw,
  });

  final int nQubits;
  final String encoding;
  final int qaoaLayers;
  final int quboTerms;
  final double? qaoaEnergy;
  final double classicalOptimum;
  final double? approximationRatio;
  final bool matchedOptimum;
  final double? pOptimum;
  final double? upliftVsUniform;

  /// P(optimum) divided by uniform over the C^P *valid* assignments — the
  /// harder baseline, and the one to quote. An ansatz that cannot emit an
  /// invalid bitstring shouldn't get credit for declining to.
  final double? upliftVsFeasibleUniform;
  final double? feasibleRate;

  /// Fraction of samples that are one-crop-per-plot. Exactly 1.0 under the
  /// XY-ring mixer — Hamming weight per block is a conserved quantity.
  final double? simplexRate;
  final double tQaoaS;
  final double tClassicalS;
  final String claim;
  final String solver;
  final bool timedOut;
  final List<ConvergencePoint> convergence;
  final Map<String, Map<String, double>> warmStart;
  final double? riskKappa;
  final int? riskScenarios;
  final double? planStdRs;
  final double? riskNeutralStdRs;
  final List<Map<String, dynamic>> profitHistogram;
  final BaselineQaoaOut? baseline;
  final Map<String, dynamic>? raw;

  factory BenchmarkOut.fromJson(Map<String, dynamic> j) => BenchmarkOut(
        nQubits: (j['n_qubits'] as num?)?.toInt() ?? 0,
        encoding: j['encoding'] as String? ?? '',
        qaoaLayers: (j['qaoa_layers'] as num?)?.toInt() ?? 0,
        quboTerms: (j['qubo_terms'] as num?)?.toInt() ?? 0,
        qaoaEnergy: (j['qaoa_energy'] as num?)?.toDouble(),
        classicalOptimum: (j['classical_optimum'] as num?)?.toDouble() ?? 0,
        approximationRatio: (j['approximation_ratio'] as num?)?.toDouble(),
        matchedOptimum: j['matched_optimum'] as bool? ?? false,
        pOptimum: (j['p_optimum'] as num?)?.toDouble(),
        upliftVsUniform: (j['uplift_vs_uniform'] as num?)?.toDouble(),
        upliftVsFeasibleUniform: (j['uplift_vs_feasible_uniform'] as num?)?.toDouble(),
        feasibleRate: (j['feasible_rate'] as num?)?.toDouble(),
        simplexRate: (j['simplex_rate'] as num?)?.toDouble(),
        tQaoaS: (j['t_qaoa_s'] as num?)?.toDouble() ?? 0,
        tClassicalS: (j['t_classical_s'] as num?)?.toDouble() ?? 0,
        claim: j['claim'] as String? ?? '',
        solver: j['solver'] as String? ?? 'sparq',
        timedOut: j['timed_out'] as bool? ?? false,
        convergence: [
          for (final c in (j['convergence'] as List<dynamic>? ?? const []))
            ConvergencePoint.fromJson(c as Map<String, dynamic>),
        ],
        warmStart: {
          for (final e in (j['warm_start'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: {
              for (final c in (e.value as Map<String, dynamic>).entries) c.key: (c.value as num).toDouble(),
            },
        },
        riskKappa: (j['risk_kappa'] as num?)?.toDouble(),
        riskScenarios: (j['risk_scenarios'] as num?)?.toInt(),
        planStdRs: (j['plan_std_rs'] as num?)?.toDouble(),
        riskNeutralStdRs: (j['risk_neutral_std_rs'] as num?)?.toDouble(),
        profitHistogram: [
          for (final h in (j['profit_histogram'] as List<dynamic>? ?? const []))
            Map<String, dynamic>.from(h as Map),
        ],
        baseline: j['baseline_qaoa'] == null
            ? null
            : BaselineQaoaOut.fromJson(j['baseline_qaoa'] as Map<String, dynamic>),
        raw: j,
      );
}

class AdvisoryOut {
  const AdvisoryOut({
    required this.fertilizer,
    required this.ph,
    required this.irrigation,
    required this.why,
  });

  final Map<String, dynamic> fertilizer;
  final Map<String, dynamic> ph;
  final Map<String, dynamic> irrigation;
  final Map<String, dynamic> why;

  factory AdvisoryOut.fromJson(Map<String, dynamic> j) => AdvisoryOut(
        fertilizer: Map<String, dynamic>.from(j['fertilizer'] as Map? ?? const {}),
        ph: Map<String, dynamic>.from(j['ph'] as Map? ?? const {}),
        irrigation: Map<String, dynamic>.from(j['irrigation'] as Map? ?? const {}),
        why: Map<String, dynamic>.from(j['why'] as Map? ?? const {}),
      );

  String get spokenSummary {
    final urea = fertilizer['urea_bags'];
    final dap = fertilizer['dap_bags'];
    final mop = fertilizer['mop_bags'];
    final phCat = ph['category'];
    final amendment = ph['amendment'];
    final dose = ph['dose_t_ha'];
    final netIrr = irrigation['net_irrigation_mm'];
    return 'Apply $urea bags urea, $dap bags DAP, and $mop bags MOP per hectare. '
        'Soil pH is $phCat — apply $dose tonnes $amendment per hectare. '
        'Net irrigation need is $netIrr millimetres after rainfall.';
  }
}

class PlanOut {
  const PlanOut({
    required this.requestId,
    required this.plan,
    required this.alternatives,
    required this.benchmark,
    required this.advisory,
    required this.dataMode,
    required this.timings,
    required this.raw,
  });

  final String requestId;
  final PlanCoreOut plan;
  final Map<String, dynamic> alternatives;
  final BenchmarkOut benchmark;
  final AdvisoryOut advisory;
  final String dataMode;
  final Map<String, dynamic> timings;
  final Map<String, dynamic> raw;

  factory PlanOut.fromJson(Map<String, dynamic> j) => PlanOut(
        requestId: j['request_id'] as String,
        plan: PlanCoreOut.fromJson(j['plan'] as Map<String, dynamic>),
        alternatives: Map<String, dynamic>.from(j['alternatives'] as Map? ?? const {}),
        benchmark: BenchmarkOut.fromJson(j['benchmark'] as Map<String, dynamic>? ?? const {}),
        advisory: AdvisoryOut.fromJson(j['advisory'] as Map<String, dynamic>? ?? const {}),
        dataMode: j['data_mode'] as String? ?? 'demo',
        timings: Map<String, dynamic>.from(j['timings'] as Map? ?? const {}),
        raw: j,
      );
}

class MapLayerOut {
  const MapLayerOut({
    required this.id,
    required this.name,
    this.url,
    required this.available,
    this.defaultOn = false,
  });

  final String id;
  final String name;
  final String? url;
  final bool available;
  final bool defaultOn;

  factory MapLayerOut.fromJson(Map<String, dynamic> j) => MapLayerOut(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        url: j['url'] as String?,
        available: j['available'] as bool? ?? false,
        defaultOn: j['default_on'] as bool? ?? false,
      );
}

class MapManifestOut {
  const MapManifestOut({
    required this.fieldId,
    required this.baseLayer,
    required this.overlays,
  });

  final String fieldId;
  final MapLayerOut baseLayer;
  final List<MapLayerOut> overlays;

  factory MapManifestOut.fromJson(Map<String, dynamic> j) => MapManifestOut(
        fieldId: j['field_id'] as String,
        baseLayer: MapLayerOut.fromJson(j['base_layer'] as Map<String, dynamic>),
        overlays: [
          for (final o in (j['overlays'] as List<dynamic>? ?? const []))
            MapLayerOut.fromJson(o as Map<String, dynamic>),
        ],
      );
}

class YieldPredictionOut {
  const YieldPredictionOut({
    required this.crop,
    required this.yieldTHa,
    required this.p10,
    required this.p90,
    required this.shap,
    required this.confidence,
  });

  final String crop;
  final double yieldTHa;
  final double p10;
  final double p90;
  final Map<String, double> shap;
  final String confidence;

  factory YieldPredictionOut.fromJson(Map<String, dynamic> j) {
    final shapRaw = j['shap'] as Map<String, dynamic>? ?? const {};
    return YieldPredictionOut(
      crop: j['crop'] as String,
      yieldTHa: (j['yield_t_ha'] as num).toDouble(),
      p10: (j['p10'] as num).toDouble(),
      p90: (j['p90'] as num).toDouble(),
      shap: {for (final e in shapRaw.entries) e.key: (e.value as num).toDouble()},
      confidence: j['confidence'] as String? ?? 'reduced',
    );
  }
}

class PredictYieldOut {
  const PredictYieldOut({
    required this.fieldId,
    required this.dataMode,
    required this.predictions,
  });

  final String fieldId;
  final String dataMode;
  final List<YieldPredictionOut> predictions;

  factory PredictYieldOut.fromJson(Map<String, dynamic> j) => PredictYieldOut(
        fieldId: j['field_id'] as String,
        dataMode: j['data_mode'] as String? ?? 'demo',
        predictions: [
          for (final p in (j['predictions'] as List<dynamic>? ?? const []))
            YieldPredictionOut.fromJson(p as Map<String, dynamic>),
        ],
      );
}

class RasterAssetOut {
  const RasterAssetOut({
    required this.id,
    required this.fieldId,
    required this.kind,
    required this.fileName,
    required this.isActive,
    required this.uploadedAt,
  });

  final String id;
  final String fieldId;
  final String kind;
  final String fileName;
  final bool isActive;
  final String uploadedAt;

  factory RasterAssetOut.fromJson(Map<String, dynamic> j) => RasterAssetOut(
        id: j['id'] as String,
        fieldId: j['field_id'] as String,
        kind: j['kind'] as String,
        fileName: j['file_name'] as String? ?? '',
        isActive: j['is_active'] as bool? ?? false,
        uploadedAt: j['uploaded_at'] as String? ?? '',
      );
}

class SignalsOut {
  const SignalsOut({
    required this.fieldId,
    required this.dataMode,
    required this.fetchedAt,
    required this.soil,
    required this.weather,
    required this.ndvi,
    required this.provenance,
  });

  final String fieldId;
  final String dataMode;
  final String fetchedAt;
  final Map<String, dynamic> soil;
  final Map<String, dynamic> weather;
  final Map<String, dynamic> ndvi;
  final Map<String, dynamic> provenance;

  factory SignalsOut.fromJson(Map<String, dynamic> j) => SignalsOut(
        fieldId: j['field_id'] as String,
        dataMode: j['data_mode'] as String? ?? 'demo',
        fetchedAt: j['fetched_at'] as String? ?? '',
        soil: Map<String, dynamic>.from(j['soil'] as Map? ?? const {}),
        weather: Map<String, dynamic>.from(j['weather'] as Map? ?? const {}),
        ndvi: Map<String, dynamic>.from(j['ndvi'] as Map? ?? const {}),
        provenance: Map<String, dynamic>.from(j['provenance'] as Map? ?? const {}),
      );
}
