import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/farmsync_api.dart';
import '../models/farm_models.dart';

/// Farm data access. Deliberately thin and cache-free.
///
/// Results are never held across farms: each provider is keyed by farm id and
/// autoDisposes, so switching farms cannot show the previous farm's soil card
/// or crop ranking (brief §4). The server is the only source of truth for what
/// belongs to whom.
class FarmRepository {
  FarmRepository(this._api);

  final FarmSyncApi _api;

  Future<List<FarmOut>> list() => _api.listFarms();

  Future<FarmOut> get(String farmId) => _api.getFarm(farmId);

  Future<({FarmOut farm, SoilCardOut soilCard})> create({
    required String name,
    required double lat,
    required double lon,
    required double areaHa,
    required SoilReadingsIn soil,
    String? sowingDate,
  }) =>
      _api.createFarm(
        name: name, lat: lat, lon: lon, areaHa: areaHa, soil: soil, sowingDate: sowingDate,
      );

  Future<void> delete(String farmId) => _api.deleteFarm(farmId);

  Future<SoilCardOut> soilCard(String farmId) => _api.getSoilCard(farmId);

  Future<SoilCardOut> addSoilCard(String farmId, SoilReadingsIn soil) => _api.addSoilCard(farmId, soil);

  Future<FeasibilityOut> feasibleCrops(String farmId) => _api.feasibleCrops(farmId);

  Future<RankResultOut> rank(
    String farmId, {
    double? waterAvailableM3,
    double? budgetRs,
    bool persist = true,
  }) =>
      _api.rankCrops(
        farmId,
        waterAvailableM3: waterAvailableM3,
        budgetRs: budgetRs,
        persist: persist,
      );

  /// Last saved ranking, or null when this farm has never been ranked.
  Future<RankResultOut?> latestRanking(String farmId) async {
    try {
      return await _api.latestRanking(farmId);
    } catch (_) {
      return null;
    }
  }

  Future<DashboardOut> dashboard() => _api.dashboard();
}

final farmRepositoryProvider = Provider<FarmRepository>((ref) => FarmRepository(ref.watch(farmSyncApiProvider)));

/// All farms on this account. Invalidate after create/delete to refresh.
final farmsProvider = FutureProvider.autoDispose<List<FarmOut>>(
  (ref) => ref.watch(farmRepositoryProvider).list(),
);

final farmProvider = FutureProvider.autoDispose.family<FarmOut, String>(
  (ref, farmId) => ref.watch(farmRepositoryProvider).get(farmId),
);

final soilCardProvider = FutureProvider.autoDispose.family<SoilCardOut, String>(
  (ref, farmId) => ref.watch(farmRepositoryProvider).soilCard(farmId),
);

final feasibleCropsProvider = FutureProvider.autoDispose.family<FeasibilityOut, String>(
  (ref, farmId) => ref.watch(farmRepositoryProvider).feasibleCrops(farmId),
);

final latestRankingProvider = FutureProvider.autoDispose.family<RankResultOut?, String>(
  (ref, farmId) => ref.watch(farmRepositoryProvider).latestRanking(farmId),
);

final dashboardProvider = FutureProvider.autoDispose<DashboardOut>(
  (ref) => ref.watch(farmRepositoryProvider).dashboard(),
);
