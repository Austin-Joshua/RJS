import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

const String _kPrefsApiBaseUrl = 'api_base_url_v1';
const String _kPrefsParcelId = 'selected_parcel_id_v1';
const Duration _httpTimeout = Duration(seconds: 45);

/// PNG from GET .../parcels/{id}/layers/{ndvi|zones}.png with ``X-Geo-Bounds`` header.
class ParcelLayerOverlay {
  const ParcelLayerOverlay({
    required this.bytes,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    this.source,
  });

  final Uint8List bytes;
  final double west;
  final double south;
  final double east;
  final double north;
  /// ``geotiff``, ``synthetic`` (API), or ``local_fallback`` (generated in-app).
  final String? source;
}

class ApiClient {
  ApiClient({String? baseUrl})
    : _compileTimeDefault =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8000/api/v1',
          );

  final String _compileTimeDefault;
  String? _prefsOverride;
  String _parcelId = '';

  /// Load saved URL and parcel selection (call from ``main()`` before ``runApp``).
  Future<void> hydrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsApiBaseUrl)?.trim();
    if (raw != null && raw.isNotEmpty) {
      _prefsOverride = _normalizeApiBaseUrl(raw);
    }
    final pid = prefs.getString(_kPrefsParcelId)?.trim();
    if (pid != null && pid.isNotEmpty) {
      _parcelId = pid;
    }
  }

  /// Active API root including ``/api/v1`` (compile-time default or Settings override).
  String get resolvedApiBaseUrl => _prefsOverride ?? _compileTimeDefault;

  /// ``http://host:port`` for ``/healthz`` (not under ``/api/v1``).
  Uri get _originUri {
    final u = Uri.parse(resolvedApiBaseUrl);
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null);
  }

  /// Persist override; pass empty string or null to clear and use compile default.
  Future<void> setApiBaseUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      _prefsOverride = null;
      await prefs.remove(_kPrefsApiBaseUrl);
      return;
    }
    final n = _normalizeApiBaseUrl(url.trim());
    _prefsOverride = n;
    await prefs.setString(_kPrefsApiBaseUrl, n);
  }

  static String _normalizeApiBaseUrl(String input) {
    var u = input.trim();
    if (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.endsWith('/api/v1')) {
      u = '$u/api/v1';
    }
    return u;
  }

  /// Quick reachability check (GET ``/healthz`` on API host).
  Future<bool> pingHealth() async {
    try {
      final r = await http
          .get(_originUri.replace(path: '/healthz'))
          .timeout(const Duration(seconds: 6));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _headers(Session session) => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Map<String, String> _authHeaders(Session session) => {
    'Authorization': 'Bearer ${session.token}',
  };

  static String? _headerInsensitive(http.Response r, String name) {
    final want = name.toLowerCase();
    for (final e in r.headers.entries) {
      if (e.key.toLowerCase() == want) {
        return e.value;
      }
    }
    return null;
  }

  String _u(String path) => '$resolvedApiBaseUrl$path';

  Future<void> _persistParcelId(String id) async {
    _parcelId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id.isEmpty) {
      await prefs.remove(_kPrefsParcelId);
    } else {
      await prefs.setString(_kPrefsParcelId, id);
    }
  }

  /// GET /parcels — returns accessible parcels for the signed-in role.
  Future<List<Map<String, dynamic>>> fetchParcelsList(Session session) async {
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse(_u('/parcels')), headers: _headers(session))
          .timeout(_httpTimeout);
    } catch (_) {
      return [];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return [];
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['parcels'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Sync [parcelId] from GET /parcels; keeps persisted selection when still valid.
  Future<void> refreshParcels(Session session) async {
    final list = await fetchParcelsList(session);
    if (list.isEmpty) {
      await _persistParcelId('');
      return;
    }
    final ids = list.map((e) => e['id'] as String).toList();
    if (_parcelId.isNotEmpty && ids.contains(_parcelId)) {
      return;
    }
    await _persistParcelId(ids.first);
  }

  /// Consultant: select which parcel Map/Dashboard use (persisted).
  Future<void> selectParcel(String parcelId) async {
    await _persistParcelId(parcelId);
  }

  String get parcelId => _parcelId;

  bool get hasSelectedParcel => _parcelId.isNotEmpty;

  /// Restore parcel id after loading from disk cache (offline / cache-only refresh).
  void setParcelId(String parcelId) {
    if (parcelId.isNotEmpty) {
      _parcelId = parcelId;
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Session session, {
    String? clientContext,
  }) async {
    final headers = Map<String, String>.from(_headers(session));
    if (clientContext != null && clientContext.isNotEmpty) {
      headers['X-Landroid-Client'] = clientContext;
    }
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse(_u(path)), headers: headers)
          .timeout(_httpTimeout);
    } catch (e) {
      throw Exception(
        'Cannot reach API at $resolvedApiBaseUrl ($e). '
        'Use the same Wi‑Fi as this PC, confirm the backend is running, '
        'or set the URL in Settings.',
      );
    }
    if (response.statusCode == 401) {
      throw Exception('Unauthorized — sign in again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (detail.length > 160) {
        detail = '${detail.substring(0, 160)}…';
      }
      throw Exception(
        'HTTP ${response.statusCode} for GET $path${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Land Consultant: create parcel and assign landowner (email, phone, or user id).
  Future<Map<String, dynamic>> createParcel(
    Session session, {
    required String name,
    String? ownerUserId,
    String? ownerEmail,
    String? ownerPhone,
    String? boundaryGeojson,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      if (ownerUserId != null && ownerUserId.trim().isNotEmpty)
        'owner_user_id': ownerUserId.trim(),
      if (ownerEmail != null && ownerEmail.trim().isNotEmpty)
        'owner_email': ownerEmail.trim(),
      if (ownerPhone != null && ownerPhone.trim().isNotEmpty)
        'owner_phone': ownerPhone.trim(),
      if (boundaryGeojson != null && boundaryGeojson.trim().isNotEmpty)
        'boundary_geojson': boundaryGeojson,
    };
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_u('/parcels')),
            headers: _headers(session),
            body: jsonEncode(body),
          )
          .timeout(_httpTimeout);
    } catch (e) {
      throw Exception('Cannot reach API ($e)');
    }
    if (response.statusCode == 401) {
      throw Exception('Unauthorized — sign in again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (detail.length > 200) {
        detail = '${detail.substring(0, 200)}…';
      }
      throw Exception(
        response.statusCode == 400
            ? (detail.isNotEmpty ? detail : 'Invalid parcel request')
            : 'Create parcel failed: HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final parcel = decoded['parcel'] as Map<String, dynamic>?;
    final id = parcel?['id'] as String?;
    if (id != null && id.isNotEmpty) {
      await _persistParcelId(id);
    } else {
      await refreshParcels(session);
    }
    return decoded;
  }

  Future<void> uploadParcelNdvi(
    Session session,
    String parcelId,
    String filePath,
    String fileName,
  ) async {
    await _multipartUpload(
      session,
      '/parcels/$parcelId/assets/orthomosaic-ndvi',
      filePath,
      fileName,
    );
  }

  Future<void> uploadParcelDem(
    Session session,
    String parcelId,
    String filePath,
    String fileName,
  ) async {
    await _multipartUpload(
      session,
      '/parcels/$parcelId/assets/dem',
      filePath,
      fileName,
    );
  }

  Future<void> _multipartUpload(
    Session session,
    String path,
    String filePath,
    String fileName,
  ) async {
    final uri = Uri.parse(_u(path));
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${session.token}';
    request.files.add(
      await http.MultipartFile.fromPath('file', filePath, filename: fileName),
    );
    late http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(_httpTimeout);
    } catch (e) {
      throw Exception('Upload failed ($e)');
    }
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Upload failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> landHealth(Session session) {
    return _request(
      '/ai/$_parcelId/land-health',
      session,
      clientContext: 'dashboard',
    );
  }

  Future<Map<String, dynamic>> plantZones(Session session) {
    return _request('/ai/$_parcelId/plant-zones', session);
  }

  Future<Map<String, dynamic>> valuation(Session session) {
    return _request(
      '/ai/$_parcelId/valuation',
      session,
      clientContext: 'dashboard',
    );
  }

  Future<Map<String, dynamic>> mapManifest(Session session) {
    return _request(
      '/parcels/$_parcelId/map-manifest',
      session,
      clientContext: 'map',
    );
  }

  Future<Map<String, dynamic>> listDocuments(Session session) async {
    return _request('/parcels/$_parcelId/documents', session);
  }

  Future<Uint8List> downloadGisSnapshotReport(Session session) async {
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(_u('/parcels/$_parcelId/gis-snapshot-report')),
            headers: _authHeaders(session),
          )
          .timeout(_httpTimeout);
    } catch (e) {
      throw Exception('Cannot download report ($e)');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Report HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<Uint8List> downloadDocument(
    Session session,
    String documentId,
  ) async {
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(
              _u('/parcels/$_parcelId/documents/$documentId/download'),
            ),
            headers: _authHeaders(session),
          )
          .timeout(_httpTimeout);
    } catch (e) {
      throw Exception('Cannot download document ($e)');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Document HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// ``layer`` is `ndvi` or `zones`. Returns null if the layer is unavailable (404).
  Future<ParcelLayerOverlay?> fetchParcelLayerPng(
    Session session,
    String parcelId,
    String layer,
  ) async {
    late http.Response response;
    try {
      final headers = Map<String, String>.from(_authHeaders(session));
      headers['X-Landroid-Client'] = 'map';
      response = await http
          .get(
            Uri.parse(_u('/parcels/$parcelId/layers/$layer.png')),
            headers: headers,
          )
          .timeout(_httpTimeout);
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) {
      return null;
    }
    final h = _headerInsensitive(response, 'x-geo-bounds');
    if (h == null || h.isEmpty) {
      return null;
    }
    final parts = h.split(',');
    if (parts.length != 4) {
      return null;
    }
    final src = _headerInsensitive(response, 'x-landroid-layer-source');
    return ParcelLayerOverlay(
      bytes: response.bodyBytes,
      west: double.parse(parts[0].trim()),
      south: double.parse(parts[1].trim()),
      east: double.parse(parts[2].trim()),
      north: double.parse(parts[3].trim()),
      source: src,
    );
  }
}
