import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/client.dart';

/// Stable folder name for an API base URL (avoids special characters in paths).
String _apiDirName(String apiBaseUrl) {
  final digest = sha256.convert(utf8.encode(apiBaseUrl.trim()));
  return digest.toString().substring(0, 24);
}

Future<Directory> _parcelRoot(String apiBaseUrl, String parcelId) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(
    p.join(support.path, 'landroid_cache', _apiDirName(apiBaseUrl), parcelId),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<Directory> _apiParcelParent(String apiBaseUrl) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(
    p.join(support.path, 'landroid_cache', _apiDirName(apiBaseUrl)),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// On-disk map manifest + raster overlays (per API root + parcel).
class ParcelMapDiskCache {
  ParcelMapDiskCache._();

  static Future<String?> findAnyParcelIdWithManifest(String apiBaseUrl) async {
    final parent = await _apiParcelParent(apiBaseUrl);
    await for (final entity in parent.list()) {
      if (entity is! Directory) {
        continue;
      }
      final id = p.basename(entity.path);
      final f = File(p.join(entity.path, 'manifest.json'));
      if (await f.exists()) {
        return id;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> readManifest(
    String apiBaseUrl,
    String parcelId,
  ) async {
    final f = File(
      p.join(
        (await _parcelRoot(apiBaseUrl, parcelId)).path,
        'manifest.json',
      ),
    );
    if (!await f.exists()) {
      return null;
    }
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeManifest(
    String apiBaseUrl,
    String parcelId,
    Map<String, dynamic> manifest,
  ) async {
    final root = await _parcelRoot(apiBaseUrl, parcelId);
    await File(p.join(root.path, 'manifest.json')).writeAsString(
      jsonEncode(manifest),
    );
  }

  static Future<ParcelLayerOverlay?> readLayer(
    String apiBaseUrl,
    String parcelId,
    String layer,
  ) async {
    final root = await _parcelRoot(apiBaseUrl, parcelId);
    final png = File(p.join(root.path, '$layer.png'));
    final meta = File(p.join(root.path, '$layer.meta.json'));
    if (!await png.exists() || !await meta.exists()) {
      return null;
    }
    try {
      final raw = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      return ParcelLayerOverlay(
        bytes: await png.readAsBytes(),
        west: (raw['west'] as num).toDouble(),
        south: (raw['south'] as num).toDouble(),
        east: (raw['east'] as num).toDouble(),
        north: (raw['north'] as num).toDouble(),
        source: raw['source'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeLayer(
    String apiBaseUrl,
    String parcelId,
    String layer,
    ParcelLayerOverlay overlay,
  ) async {
    final root = await _parcelRoot(apiBaseUrl, parcelId);
    await File(p.join(root.path, '$layer.png')).writeAsBytes(
      Uint8List.fromList(overlay.bytes),
    );
    await File(p.join(root.path, '$layer.meta.json')).writeAsString(
      jsonEncode({
        'west': overlay.west,
        'south': overlay.south,
        'east': overlay.east,
        'north': overlay.north,
        'source': overlay.source,
      }),
    );
  }

  /// Deletes cached map data for [apiBaseUrl] and [parcelId].
  static Future<void> clearParcel(String apiBaseUrl, String parcelId) async {
    final dir = await _parcelRoot(apiBaseUrl, parcelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// Cached dashboard AI bundle (full JSON bodies from ``/ai/...`` endpoints).
class DashboardDiskCache {
  DashboardDiskCache._();

  static Future<File> _file(String apiBaseUrl, String parcelId) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      p.join(support.path, 'landroid_cache', _apiDirName(apiBaseUrl), '_dashboard'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, '$parcelId.json'));
  }

  static Future<Map<String, dynamic>?> read(String apiBaseUrl, String parcelId) async {
    final f = await _file(apiBaseUrl, parcelId);
    if (!await f.exists()) {
      return null;
    }
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    String apiBaseUrl,
    String parcelId, {
    required Map<String, dynamic> landHealth,
    required Map<String, dynamic> plantZones,
    required Map<String, dynamic> valuation,
  }) async {
    final f = await _file(apiBaseUrl, parcelId);
    await f.writeAsString(
      jsonEncode({
        'landHealth': landHealth,
        'plantZones': plantZones,
        'valuation': valuation,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<void> clear(String apiBaseUrl, String parcelId) async {
    final f = await _file(apiBaseUrl, parcelId);
    if (await f.exists()) {
      await f.delete();
    }
  }
}

/// Removes all on-disk cache for an API base URL (map layers + dashboard).
Future<void> clearAllDiskCacheForApi(String apiBaseUrl) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(
    p.join(support.path, 'landroid_cache', _apiDirName(apiBaseUrl)),
  );
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
