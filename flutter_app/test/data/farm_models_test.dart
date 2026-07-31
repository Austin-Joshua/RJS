import 'package:flutter_app/data/models/farm_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing guards for the farm payloads. These shapes come straight from
/// backend/app/api/v1/farms.py; if the contract drifts, this fails here rather
/// than as a null on a farmer's screen.
void main() {
  group('SoilCardOut', () {
    test('keeps the farmer\'s own readings and their classes', () {
      final card = SoilCardOut.fromJson(const {
        'soil_type': 'alluvial',
        'soil_type_meta': {'name_en': 'Alluvial'},
        'readings': {'n_kg_ha': 240.0, 'p_kg_ha': 18.0, 'ph': 6.8, 'ec_ds_m': null},
        'classes': {'n_kg_ha': 'low', 'p_kg_ha': 'medium'},
        'ph': {'value': 6.8, 'category': 'neutral', 'note': 'Neutral.'},
        'ec': {'value': null, 'category': 'unknown'},
        'water': {'per_ha_m3': 6000.0, 'category': 'high'},
        'summary': 'Alluvial soil, neutral.',
        'caveat': 'Confirm with a soil test.',
        'warnings': ['No EC reading.'],
      });

      expect(card.soilTypeName, 'Alluvial');
      expect(card.readings['n_kg_ha'], 240.0);
      expect(card.readings['ec_ds_m'], isNull, reason: 'a missing reading must stay missing, not become 0');
      expect(card.classes['n_kg_ha'], 'low');
      expect(card.ph['category'], 'neutral');
      expect(card.warnings.single, 'No EC reading.');
    });
  });

  group('FarmOut', () {
    test('reads the nested latest ranking', () {
      final farm = FarmOut.fromJson(const {
        'id': 'farm-1',
        'name': 'North field',
        'centroid': {'lat': 10.75, 'lon': 79.05},
        'area_ha': 1.5,
        'district': 'Thanjavur',
        'state': 'Tamil Nadu',
        'has_soil_card': true,
        'latest_ranking': {
          'sequence': {
            'sequence': ['groundnut', 'paddy', 'black_gram'],
          },
          'total_value_rs': 121260.0,
        },
      });

      expect(farm.isRanked, isTrue);
      expect(farm.latestSequence, ['groundnut', 'paddy', 'black_gram']);
      expect(farm.latestValueRs, 121260.0);
    });

    test('an unranked farm is not mistaken for a ranked one', () {
      final farm = FarmOut.fromJson(const {
        'id': 'farm-2',
        'name': 'New plot',
        'centroid': {'lat': 10.0, 'lon': 79.0},
        'area_ha': 0.8,
        'district': 'Thanjavur',
        'state': 'Tamil Nadu',
        'has_soil_card': false,
        'latest_ranking': null,
      });

      expect(farm.isRanked, isFalse);
      expect(farm.hasSoilCard, isFalse);
      expect(farm.latestValueRs, isNull);
    });
  });

  group('RankResultOut', () {
    const payload = {
      'field_id': 'farm-1',
      'feasibility': {
        'feasible': [
          {'crop': 'paddy', 'name_en': 'Paddy', 'feasible': true, 'reasons': ['pH in range.'], 'seasons': ['kharif']},
        ],
        'excluded': [
          {
            'crop': 'sugarcane',
            'name_en': 'Sugarcane',
            'feasible': false,
            'reasons': ['Needs ~27,000 m³ of water but only 11,000 m³ is available this season.'],
          },
        ],
        'rotation_candidates': ['paddy', 'groundnut', 'black_gram'],
      },
      'ranking': {
        'solver': 'sparq_rotation',
        'seasons': ['kharif', 'rabi', 'summer'],
        'sequence': ['groundnut', 'paddy', 'black_gram'],
        'ranked_crops': [
          {
            'rank': 1,
            'crop': 'groundnut',
            'name_en': 'Groundnut',
            'season': 'kharif',
            'standalone_value_rs': 44000.0,
            'realised_value_rs': 44000.0,
            'rotation_multiplier': 1.0,
            'n_credit_rs': 0.0,
            'why': 'First season of the cycle.',
            'yield_t_ha': 1.75,
            'p10': 1.2,
            'p90': 3.5,
          },
        ],
        'total_value_rs': 121260.0,
        'matched_exact_optimum': true,
      },
      'baselines': {
        'sorted_by_yield': {
          'sequence': ['paddy', 'paddy', 'groundnut'],
          'value_rs': 98400.0,
          'gap_rs': 22860.0,
          'is_suboptimal': true,
        },
        'greedy_with_lookback': {
          'sequence': ['groundnut', 'paddy', 'paddy'],
          'value_rs': 110000.0,
          'gap_rs': 11260.0,
          'is_suboptimal': true,
        },
      },
      'quantum': {
        'n_qubits': 9,
        'encoding': 'rotation_simplex',
        'layers': 3,
        'qubo_terms': 38,
        'simplex_rate': 1.0,
        'feasible_rate': 0.61,
        'wall_time_s': 2.2,
        'convergence': [
          {'layer': 1, 'iteration': 1, 'cvar_energy': -0.4},
          {'layer': 1, 'iteration': 2, 'cvar_energy': -0.6},
        ],
        'measurements': [
          {
            'rank': 1,
            'bitstring': '100010001',
            'probability': 0.61,
            'label': {
              'sequence': ['groundnut', 'paddy', 'black_gram'],
              'value_rs': 121260.0,
            },
          },
        ],
        'circuit': {
          'n_qubits': 9,
          'blocks': [
            [0, 1, 2],
            [3, 4, 5],
          ],
          'operations': [
            {'stage': 'init', 'gate': 'X', 'wires': [0]},
            {'stage': 'mixer', 'layer': 1, 'gate': 'IsingXY', 'wires': [0, 1], 'label': '2β1'},
          ],
          'gate_counts': {'total': 60, 'two_qubit': 48, 'entangling_mixer': 36},
          'invariant': 'Hamming weight per block is conserved.',
        },
        'claim': 'Read off the measurement distribution.',
      },
      'advisory': {
        'fertilizer': {'urea_bags': 5},
      },
      'data_mode': 'live',
      'timings': {'quantum_ms': 2200.0},
    };

    test('parses the ranking, quantum evidence, and both baselines', () {
      final r = RankResultOut.fromJson(Map<String, dynamic>.from(payload));

      expect(r.ranking!.solver, 'sparq_rotation');
      expect(r.ranking!.rankedCrops.single.rank, 1);
      expect(r.ranking!.matchedExactOptimum, isTrue);

      // The measured proof that sorting is the wrong answer here.
      expect(r.sortedBaseline!.isSuboptimal, isTrue);
      expect(r.sortedBaseline!.gapRs, 22860.0);
      expect(r.greedyBaseline!.isSuboptimal, isTrue);

      // §3 requires the quantum contribution to be visible.
      final q = r.quantum!;
      expect(q.simplexRate, 1.0);
      expect(q.operations.any((o) => o.gate == 'IsingXY'), isTrue);
      expect(q.blocks.length, 2);
      expect(q.gateCounts['entangling_mixer'], 36);
      expect(q.convergence, [-0.4, -0.6]);
      expect(q.invariant, contains('Hamming weight'));

      // Rank 1 is the most-measured outcome, decoded to a crop order.
      expect(q.measurements.first.sequence, ['groundnut', 'paddy', 'black_gram']);
      expect(q.measurements.first.probability, 0.61);

      // An excluded crop leads with why it was excluded.
      expect(r.feasibility.excluded.single.reasons.first, contains('water'));
      expect(r.advisory!['fertilizer'], isNotNull);
    });

    test('handles a farm with too few crops to sequence', () {
      final r = RankResultOut.fromJson(const {
        'field_id': 'farm-3',
        'feasibility': {'feasible': [], 'excluded': [], 'rotation_candidates': []},
        'ranking': null,
        'error': 'Fewer than two rotation-eligible crops passed the gates.',
        'data_mode': 'degraded',
        'timings': {},
      });

      expect(r.ranking, isNull);
      expect(r.quantum, isNull);
      expect(r.error, contains('Fewer than two'));
    });
  });

  group('DashboardOut', () {
    test('aggregates totals and per-farm issues', () {
      final d = DashboardOut.fromJson(const {
        'totals': {
          'farms': 2,
          'total_area_ha': 4.0,
          'farms_ranked': 1,
          'farms_awaiting_ranking': 1,
          'combined_projected_value_rs': 121260.0,
        },
        'farms': [
          {
            'farm_id': 'a',
            'name': 'Dash A',
            'district': 'Thanjavur',
            'area_ha': 1.5,
            'soil_summary': 'Alluvial soil, neutral.',
            'ranked': true,
            'sequence_names': ['Groundnut', 'Paddy'],
            'total_value_rs': 121260.0,
            'issues': [],
          },
          {
            'farm_id': 'b',
            'name': 'Dash B',
            'district': 'Thanjavur',
            'area_ha': 2.5,
            'ranked': false,
            'sequence_names': [],
            'issues': ['no crop ranking yet'],
          },
        ],
        'crop_frequency': {'groundnut': 2, 'paddy': 1},
      });

      expect(d.farms, 2);
      expect(d.totalAreaHa, 4.0);
      expect(d.farmsAwaiting, 1);
      expect(d.rows.last.issues, ['no crop ranking yet']);
      expect(d.cropFrequency['groundnut'], 2);
    });
  });

  group('SoilReadingsIn', () {
    test('omits optional fields rather than sending nulls', () {
      const readings = SoilReadingsIn(
        soilType: 'alluvial',
        nKgHa: 240,
        pKgHa: 18,
        kKgHa: 190,
        ph: 6.8,
      );
      final json = readings.toJson();

      expect(json['soil_type'], 'alluvial');
      expect(json.containsKey('oc_pct'), isFalse);
      expect(json.containsKey('ec_ds_m'), isFalse);
      expect(json.containsKey('water_available_m3'), isFalse);
    });

    test('includes optional fields when the farmer supplied them', () {
      const readings = SoilReadingsIn(
        soilType: 'clay',
        nKgHa: 300,
        pKgHa: 22,
        kKgHa: 210,
        ph: 7.2,
        ocPct: 0.6,
        ecDsM: 0.4,
        waterAvailableM3: 9000,
      );
      final json = readings.toJson();

      expect(json['oc_pct'], 0.6);
      expect(json['ec_ds_m'], 0.4);
      expect(json['water_available_m3'], 9000);
    });
  });
}
