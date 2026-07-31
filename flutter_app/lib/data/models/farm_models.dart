/// Typed models for the farm flow, matching backend/app/api/v1/farms.py.
///
/// Everything here is per-farm. Nothing is shared or cached across farms —
/// each screen holds the payload the API returned for the farm it is showing.
library;

class SoilCardOut {
  const SoilCardOut({
    required this.soilType,
    required this.soilTypeName,
    required this.readings,
    required this.classes,
    required this.ph,
    required this.ec,
    required this.water,
    required this.summary,
    required this.caveat,
    required this.warnings,
  });

  final String soilType;
  final String soilTypeName;

  /// Exactly what the farmer typed, echoed back untouched.
  final Map<String, double?> readings;

  /// ICAR low / medium / high per nutrient.
  final Map<String, String> classes;
  final Map<String, dynamic> ph;
  final Map<String, dynamic> ec;
  final Map<String, dynamic> water;
  final String summary;
  final String caveat;
  final List<String> warnings;

  factory SoilCardOut.fromJson(Map<String, dynamic> j) => SoilCardOut(
        soilType: j['soil_type'] as String? ?? '',
        soilTypeName: (j['soil_type_meta'] as Map<String, dynamic>? ?? const {})['name_en'] as String? ??
            (j['soil_type'] as String? ?? ''),
        readings: {
          for (final e in (j['readings'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: (e.value as num?)?.toDouble(),
        },
        classes: {
          for (final e in (j['classes'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: e.value as String,
        },
        ph: Map<String, dynamic>.from(j['ph'] as Map? ?? const {}),
        ec: Map<String, dynamic>.from(j['ec'] as Map? ?? const {}),
        water: Map<String, dynamic>.from(j['water'] as Map? ?? const {}),
        summary: j['summary'] as String? ?? '',
        caveat: j['caveat'] as String? ?? '',
        warnings: [for (final w in (j['warnings'] as List<dynamic>? ?? const [])) w as String],
      );
}

class FarmOut {
  const FarmOut({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.areaHa,
    required this.district,
    required this.state,
    required this.hasSoilCard,
    this.soilCard,
    this.latestSequence = const [],
    this.latestValueRs,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double areaHa;
  final String district;
  final String state;
  final bool hasSoilCard;
  final SoilCardOut? soilCard;
  final List<String> latestSequence;
  final double? latestValueRs;

  bool get isRanked => latestSequence.isNotEmpty;

  factory FarmOut.fromJson(Map<String, dynamic> j) {
    final c = j['centroid'] as Map<String, dynamic>? ?? const {};
    final ranking = j['latest_ranking'] as Map<String, dynamic>?;
    final seq = _sequenceFromJson(ranking?['sequence']);
    return FarmOut(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      lat: (c['lat'] as num?)?.toDouble() ?? 0,
      lon: (c['lon'] as num?)?.toDouble() ?? 0,
      areaHa: (j['area_ha'] as num?)?.toDouble() ?? 0,
      district: j['district'] as String? ?? '',
      state: j['state'] as String? ?? '',
      hasSoilCard: j['has_soil_card'] as bool? ?? false,
      soilCard: j['soil_card'] == null ? null : SoilCardOut.fromJson(j['soil_card'] as Map<String, dynamic>),
      latestSequence: seq,
      latestValueRs: (ranking?['total_value_rs'] as num?)?.toDouble(),
    );
  }

  /// Accepts `["paddy", …]`, `{"sequence":[…]}`, or a space-joined string.
  static List<String> _sequenceFromJson(dynamic raw) {
    if (raw is List) return [for (final s in raw) '$s'];
    if (raw is Map) return _sequenceFromJson(raw['sequence']);
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}

class CropVerdictOut {
  const CropVerdictOut({
    required this.crop,
    required this.nameEn,
    required this.nameTa,
    required this.feasible,
    required this.reasons,
    required this.warnings,
    required this.waterRequiredM3,
    required this.seasons,
    required this.rotationEligible,
  });

  final String crop;
  final String nameEn;
  final String nameTa;
  final bool feasible;

  /// For an excluded crop the first entry is why it was excluded.
  final List<String> reasons;
  final List<String> warnings;
  final double waterRequiredM3;
  final List<String> seasons;
  final bool rotationEligible;

  factory CropVerdictOut.fromJson(Map<String, dynamic> j) => CropVerdictOut(
        crop: j['crop'] as String,
        nameEn: j['name_en'] as String? ?? j['crop'] as String,
        nameTa: j['name_ta'] as String? ?? '',
        feasible: j['feasible'] as bool? ?? false,
        reasons: [for (final r in (j['reasons'] as List<dynamic>? ?? const [])) r as String],
        warnings: [for (final w in (j['warnings'] as List<dynamic>? ?? const [])) w as String],
        waterRequiredM3: (j['water_required_m3'] as num?)?.toDouble() ?? 0,
        seasons: [for (final s in (j['seasons'] as List<dynamic>? ?? const [])) s as String],
        rotationEligible: j['rotation_eligible'] as bool? ?? true,
      );
}

class FeasibilityOut {
  const FeasibilityOut({
    required this.feasible,
    required this.excluded,
    required this.rotationCandidates,
  });

  final List<CropVerdictOut> feasible;
  final List<CropVerdictOut> excluded;
  final List<String> rotationCandidates;

  factory FeasibilityOut.fromJson(Map<String, dynamic> j) => FeasibilityOut(
        feasible: [
          for (final r in (j['feasible'] as List<dynamic>? ?? const []))
            CropVerdictOut.fromJson(r as Map<String, dynamic>),
        ],
        excluded: [
          for (final r in (j['excluded'] as List<dynamic>? ?? const []))
            CropVerdictOut.fromJson(r as Map<String, dynamic>),
        ],
        rotationCandidates: [
          for (final c in (j['rotation_candidates'] as List<dynamic>? ?? const [])) c as String,
        ],
      );
}

/// One rank in the quantum-ordered rotation.
class RankedCropOut {
  const RankedCropOut({
    required this.rank,
    required this.crop,
    required this.nameEn,
    required this.nameTa,
    required this.season,
    required this.standaloneValueRs,
    required this.realisedValueRs,
    required this.rotationMultiplier,
    required this.nCreditRs,
    required this.why,
    required this.yieldTHa,
    required this.p10,
    required this.p90,
  });

  final int rank;
  final String crop;
  final String nameEn;
  final String nameTa;
  final String season;

  /// What the crop is worth on its own — what a sort would have ranked by.
  final double standaloneValueRs;

  /// What it is actually worth in this slot, after the predecessor effect.
  final double realisedValueRs;
  final double rotationMultiplier;
  final double nCreditRs;
  final String why;
  final double yieldTHa;
  final double p10;
  final double p90;

  factory RankedCropOut.fromJson(Map<String, dynamic> j) => RankedCropOut(
        rank: (j['rank'] as num).toInt(),
        crop: j['crop'] as String,
        nameEn: j['name_en'] as String? ?? j['crop'] as String,
        nameTa: j['name_ta'] as String? ?? '',
        season: j['season'] as String? ?? '',
        standaloneValueRs: (j['standalone_value_rs'] as num?)?.toDouble() ?? 0,
        realisedValueRs: (j['realised_value_rs'] as num?)?.toDouble() ?? 0,
        rotationMultiplier: (j['rotation_multiplier'] as num?)?.toDouble() ?? 1,
        nCreditRs: (j['n_credit_rs'] as num?)?.toDouble() ?? 0,
        why: j['why'] as String? ?? '',
        yieldTHa: (j['yield_t_ha'] as num?)?.toDouble() ?? 0,
        p10: (j['p10'] as num?)?.toDouble() ?? 0,
        p90: (j['p90'] as num?)?.toDouble() ?? 0,
      );
}

/// A crop's standing on this farm by profitability — the "best crop for my
/// land" question, distinct from where it lands in the planting order.
class CropRankOut {
  const CropRankOut({
    required this.rank,
    required this.crop,
    required this.nameEn,
    required this.standaloneValueRs,
    required this.inPlan,
    required this.seasonsInPlan,
    required this.yieldTHa,
    this.bestSlotValueRs,
  });

  final int rank;
  final String crop;
  final String nameEn;
  final double standaloneValueRs;
  final bool inPlan;
  final List<String> seasonsInPlan;
  final double yieldTHa;
  final double? bestSlotValueRs;

  factory CropRankOut.fromJson(Map<String, dynamic> j) => CropRankOut(
        rank: (j['rank'] as num).toInt(),
        crop: j['crop'] as String,
        nameEn: j['name_en'] as String? ?? j['crop'] as String,
        standaloneValueRs: (j['standalone_value_rs'] as num?)?.toDouble() ?? 0,
        inPlan: j['in_plan'] as bool? ?? false,
        seasonsInPlan: [for (final s in (j['seasons_in_plan'] as List<dynamic>? ?? const [])) s as String],
        yieldTHa: (j['yield_t_ha'] as num?)?.toDouble() ?? 0,
        bestSlotValueRs: (j['best_slot_value_rs'] as num?)?.toDouble(),
      );
}

class BaselineOut {
  const BaselineOut({required this.sequence, required this.valueRs, required this.gapRs, required this.isSuboptimal});

  final List<String> sequence;
  final double valueRs;
  final double gapRs;
  final bool isSuboptimal;

  factory BaselineOut.fromJson(Map<String, dynamic> j) => BaselineOut(
        sequence: [for (final s in (j['sequence'] as List<dynamic>? ?? const [])) s as String],
        valueRs: (j['value_rs'] as num?)?.toDouble() ?? 0,
        gapRs: (j['gap_rs'] as num?)?.toDouble() ?? 0,
        isSuboptimal: j['is_suboptimal'] as bool? ?? false,
      );
}

class MeasuredOutcome {
  const MeasuredOutcome({
    required this.rank,
    required this.bitstring,
    required this.probability,
    required this.sequence,
    this.valueRs,
  });

  final int rank;
  final String bitstring;
  final double probability;
  final List<String> sequence;
  final double? valueRs;

  factory MeasuredOutcome.fromJson(Map<String, dynamic> j) {
    final label = j['label'] as Map<String, dynamic>?;
    return MeasuredOutcome(
      rank: (j['rank'] as num?)?.toInt() ?? 0,
      bitstring: j['bitstring'] as String? ?? '',
      probability: (j['probability'] as num?)?.toDouble() ?? 0,
      sequence: [for (final s in (label?['sequence'] as List<dynamic>? ?? const [])) s as String],
      valueRs: (label?['value_rs'] as num?)?.toDouble(),
    );
  }
}

class CircuitOp {
  const CircuitOp({required this.stage, required this.gate, required this.wires, this.layer, this.label});

  final String stage; // init | cost | mixer
  final String gate;
  final List<int> wires;
  final int? layer;
  final String? label;

  factory CircuitOp.fromJson(Map<String, dynamic> j) => CircuitOp(
        stage: j['stage'] as String? ?? '',
        gate: j['gate'] as String? ?? '',
        wires: [for (final w in (j['wires'] as List<dynamic>? ?? const [])) (w as num).toInt()],
        layer: (j['layer'] as num?)?.toInt(),
        label: j['label'] as String?,
      );
}

class QuantumOut {
  const QuantumOut({
    required this.nQubits,
    required this.encoding,
    required this.layers,
    required this.quboTerms,
    required this.simplexRate,
    required this.feasibleRate,
    required this.wallTimeS,
    required this.convergence,
    required this.measurements,
    required this.operations,
    required this.blocks,
    required this.invariant,
    required this.claim,
    required this.gateCounts,
    required this.timedOut,
  });

  final int nQubits;
  final String encoding;
  final int layers;
  final int quboTerms;

  /// Fraction of samples that are one-crop-per-season. 1.0 by symmetry.
  final double simplexRate;
  final double feasibleRate;
  final double wallTimeS;
  final List<double> convergence;
  final List<MeasuredOutcome> measurements;
  final List<CircuitOp> operations;
  final List<List<int>> blocks;
  final String invariant;
  final String claim;
  final Map<String, int> gateCounts;
  final bool timedOut;

  factory QuantumOut.fromJson(Map<String, dynamic> j) {
    final circuit = j['circuit'] as Map<String, dynamic>? ?? const {};
    return QuantumOut(
      nQubits: (j['n_qubits'] as num?)?.toInt() ?? 0,
      encoding: j['encoding'] as String? ?? '',
      layers: (j['layers'] as num?)?.toInt() ?? 0,
      quboTerms: (j['qubo_terms'] as num?)?.toInt() ?? 0,
      simplexRate: (j['simplex_rate'] as num?)?.toDouble() ?? 0,
      feasibleRate: (j['feasible_rate'] as num?)?.toDouble() ?? 0,
      wallTimeS: (j['wall_time_s'] as num?)?.toDouble() ?? 0,
      convergence: [
        for (final c in (j['convergence'] as List<dynamic>? ?? const []))
          ((c as Map<String, dynamic>)['cvar_energy'] as num).toDouble(),
      ],
      measurements: [
        for (final m in (j['measurements'] as List<dynamic>? ?? const []))
          MeasuredOutcome.fromJson(m as Map<String, dynamic>),
      ],
      operations: [
        for (final o in (circuit['operations'] as List<dynamic>? ?? const []))
          CircuitOp.fromJson(o as Map<String, dynamic>),
      ],
      blocks: [
        for (final b in (circuit['blocks'] as List<dynamic>? ?? const []))
          [for (final w in (b as List<dynamic>)) (w as num).toInt()],
      ],
      invariant: circuit['invariant'] as String? ?? '',
      claim: j['claim'] as String? ?? '',
      gateCounts: {
        for (final e in (circuit['gate_counts'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: (e.value as num).toInt(),
      },
      timedOut: j['timed_out'] as bool? ?? false,
    );
  }
}

class RankingOut {
  const RankingOut({
    required this.solver,
    required this.seasons,
    required this.sequence,
    required this.rankedCrops,
    required this.cropRanking,
    required this.totalValueRs,
    required this.matchedExactOptimum,
  });

  final String solver;
  final List<String> seasons;
  final List<String> sequence;
  /// Planting order — what the optimiser decided, season by season.
  final List<RankedCropOut> rankedCrops;

  /// Profitability order over the feasible crops, best first (§2.5).
  final List<CropRankOut> cropRanking;
  final double totalValueRs;
  final bool matchedExactOptimum;

  factory RankingOut.fromJson(Map<String, dynamic> j) => RankingOut(
        solver: j['solver'] as String? ?? '',
        seasons: [for (final s in (j['seasons'] as List<dynamic>? ?? const [])) s as String],
        sequence: [for (final s in (j['sequence'] as List<dynamic>? ?? const [])) s as String],
        rankedCrops: [
          for (final r in (j['ranked_crops'] as List<dynamic>? ?? const []))
            RankedCropOut.fromJson(r as Map<String, dynamic>),
        ],
        cropRanking: [
          for (final r in (j['crop_ranking'] as List<dynamic>? ?? const []))
            CropRankOut.fromJson(r as Map<String, dynamic>),
        ],
        totalValueRs: (j['total_value_rs'] as num?)?.toDouble() ?? 0,
        matchedExactOptimum: j['matched_exact_optimum'] as bool? ?? false,
      );
}

class RankResultOut {
  const RankResultOut({
    required this.farmId,
    required this.feasibility,
    this.ranking,
    this.quantum,
    this.sortedBaseline,
    this.greedyBaseline,
    this.advisory,
    this.error,
    this.note,
    required this.dataMode,
    required this.timings,
  });

  final String farmId;
  final FeasibilityOut feasibility;
  final RankingOut? ranking;
  final QuantumOut? quantum;
  final BaselineOut? sortedBaseline;
  final BaselineOut? greedyBaseline;
  final Map<String, dynamic>? advisory;
  final String? error;

  /// Set when the pipeline took a shortcut worth telling the farmer about —
  /// e.g. only one crop passed the gates, so no circuit was run.
  final String? note;
  final String dataMode;
  final Map<String, dynamic> timings;

  factory RankResultOut.fromJson(Map<String, dynamic> j) {
    final baselines = j['baselines'] as Map<String, dynamic>?;
    return RankResultOut(
      farmId: j['field_id'] as String? ?? '',
      feasibility: FeasibilityOut.fromJson(j['feasibility'] as Map<String, dynamic>? ?? const {}),
      ranking: j['ranking'] == null ? null : RankingOut.fromJson(j['ranking'] as Map<String, dynamic>),
      quantum: j['quantum'] == null ? null : QuantumOut.fromJson(j['quantum'] as Map<String, dynamic>),
      sortedBaseline: baselines?['sorted_by_yield'] == null
          ? null
          : BaselineOut.fromJson(baselines!['sorted_by_yield'] as Map<String, dynamic>),
      greedyBaseline: baselines?['greedy_with_lookback'] == null
          ? null
          : BaselineOut.fromJson(baselines!['greedy_with_lookback'] as Map<String, dynamic>),
      advisory: j['advisory'] == null ? null : Map<String, dynamic>.from(j['advisory'] as Map),
      error: j['error'] as String?,
      note: j['note'] as String?,
      dataMode: j['data_mode'] as String? ?? 'degraded',
      timings: Map<String, dynamic>.from(j['timings'] as Map? ?? const {}),
    );
  }
}

class DashboardFarmRow {
  const DashboardFarmRow({
    required this.farmId,
    required this.name,
    required this.district,
    required this.areaHa,
    required this.soilSummary,
    required this.ranked,
    required this.sequenceNames,
    required this.totalValueRs,
    required this.issues,
  });

  final String farmId;
  final String name;
  final String district;
  final double areaHa;
  final String? soilSummary;
  final bool ranked;
  final List<String> sequenceNames;
  final double? totalValueRs;
  final List<String> issues;

  factory DashboardFarmRow.fromJson(Map<String, dynamic> j) => DashboardFarmRow(
        farmId: j['farm_id'] as String,
        name: j['name'] as String? ?? '',
        district: j['district'] as String? ?? '',
        areaHa: (j['area_ha'] as num?)?.toDouble() ?? 0,
        soilSummary: j['soil_summary'] as String?,
        ranked: j['ranked'] as bool? ?? false,
        sequenceNames: [for (final s in (j['sequence_names'] as List<dynamic>? ?? const [])) s as String],
        totalValueRs: (j['total_value_rs'] as num?)?.toDouble(),
        issues: [for (final i in (j['issues'] as List<dynamic>? ?? const [])) i as String],
      );
}

class DashboardQuantumOut {
  const DashboardQuantumOut({
    required this.farmsOptimised,
    this.avgFeasibleRate,
    this.avgSimplexRate,
    this.avgWallTimeS,
    required this.beatsSimpleSortCount,
    required this.extraValueVsSortRs,
    required this.plainSummary,
  });

  final int farmsOptimised;
  final double? avgFeasibleRate;
  final double? avgSimplexRate;
  final double? avgWallTimeS;
  final int beatsSimpleSortCount;
  final double extraValueVsSortRs;
  final String plainSummary;

  factory DashboardQuantumOut.fromJson(Map<String, dynamic> j) => DashboardQuantumOut(
        farmsOptimised: (j['farms_optimised'] as num?)?.toInt() ?? 0,
        avgFeasibleRate: (j['avg_feasible_rate'] as num?)?.toDouble(),
        avgSimplexRate: (j['avg_simplex_rate'] as num?)?.toDouble(),
        avgWallTimeS: (j['avg_wall_time_s'] as num?)?.toDouble(),
        beatsSimpleSortCount: (j['beats_simple_sort_count'] as num?)?.toInt() ?? 0,
        extraValueVsSortRs: (j['extra_value_vs_sort_rs'] as num?)?.toDouble() ?? 0,
        plainSummary: j['plain_summary'] as String? ?? '',
      );
}

class LandVariableRow {
  const LandVariableRow({
    required this.farmId,
    required this.name,
    this.nKgHa,
    this.pKgHa,
    this.kKgHa,
    this.ph,
    required this.classes,
  });

  final String farmId;
  final String name;
  final double? nKgHa;
  final double? pKgHa;
  final double? kKgHa;
  final double? ph;
  final Map<String, String> classes;

  factory LandVariableRow.fromJson(Map<String, dynamic> j) => LandVariableRow(
        farmId: j['farm_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        nKgHa: (j['n_kg_ha'] as num?)?.toDouble(),
        pKgHa: (j['p_kg_ha'] as num?)?.toDouble(),
        kKgHa: (j['k_kg_ha'] as num?)?.toDouble(),
        ph: (j['ph'] as num?)?.toDouble(),
        classes: {
          for (final e in (j['classes'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: e.value as String,
        },
      );
}

class DashboardOut {
  const DashboardOut({
    required this.farms,
    required this.totalAreaHa,
    required this.farmsRanked,
    required this.farmsAwaiting,
    required this.combinedValueRs,
    required this.rows,
    required this.cropFrequency,
    this.quantum,
    this.landVariables = const [],
  });

  final int farms;
  final double totalAreaHa;
  final int farmsRanked;
  final int farmsAwaiting;
  final double combinedValueRs;
  final List<DashboardFarmRow> rows;
  final Map<String, int> cropFrequency;
  final DashboardQuantumOut? quantum;
  final List<LandVariableRow> landVariables;

  factory DashboardOut.fromJson(Map<String, dynamic> j) {
    final t = j['totals'] as Map<String, dynamic>? ?? const {};
    return DashboardOut(
      farms: (t['farms'] as num?)?.toInt() ?? 0,
      totalAreaHa: (t['total_area_ha'] as num?)?.toDouble() ?? 0,
      farmsRanked: (t['farms_ranked'] as num?)?.toInt() ?? 0,
      farmsAwaiting: (t['farms_awaiting_ranking'] as num?)?.toInt() ?? 0,
      combinedValueRs: (t['combined_projected_value_rs'] as num?)?.toDouble() ?? 0,
      rows: [
        for (final r in (j['farms'] as List<dynamic>? ?? const []))
          DashboardFarmRow.fromJson(r as Map<String, dynamic>),
      ],
      cropFrequency: {
        for (final e in (j['crop_frequency'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: (e.value as num).toInt(),
      },
      quantum: j['quantum'] == null
          ? null
          : DashboardQuantumOut.fromJson(j['quantum'] as Map<String, dynamic>),
      landVariables: [
        for (final r in (j['land_variables'] as List<dynamic>? ?? const []))
          LandVariableRow.fromJson(r as Map<String, dynamic>),
      ],
    );
  }
}

/// Soil readings the farmer enters (§2.2).
class SoilReadingsIn {
  const SoilReadingsIn({
    required this.soilType,
    required this.nKgHa,
    required this.pKgHa,
    required this.kKgHa,
    required this.ph,
    this.ocPct,
    this.ecDsM,
    this.moisturePct,
    this.waterAvailableM3,
  });

  final String soilType;
  final double nKgHa;
  final double pKgHa;
  final double kKgHa;
  final double ph;
  final double? ocPct;
  final double? ecDsM;
  final double? moisturePct;
  final double? waterAvailableM3;

  Map<String, dynamic> toJson() => {
        'soil_type': soilType,
        'n_kg_ha': nKgHa,
        'p_kg_ha': pKgHa,
        'k_kg_ha': kKgHa,
        'ph': ph,
        if (ocPct != null) 'oc_pct': ocPct,
        if (ecDsM != null) 'ec_ds_m': ecDsM,
        if (moisturePct != null) 'moisture_pct': moisturePct,
        if (waterAvailableM3 != null) 'water_available_m3': waterAvailableM3,
      };
}

/// Soil texture options offered in the entry form, matching the backend table.
const soilTypeOptions = <String, String>{
  'alluvial': 'Alluvial',
  'black': 'Black (regur)',
  'red': 'Red',
  'laterite': 'Laterite',
  'clay': 'Clay',
  'clay_loam': 'Clay loam',
  'loam': 'Loam',
  'sandy_loam': 'Sandy loam',
  'sandy': 'Sandy',
};

const seasonLabels = <String, String>{
  'kharif': 'Kharif (Jun–Oct)',
  'rabi': 'Rabi (Oct–Feb)',
  'summer': 'Summer (Feb–May)',
};
