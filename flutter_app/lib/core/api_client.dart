import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_token.dart';
import 'env.dart';

/// Paths that the backend leaves unauthenticated.
const _publicSuffixes = <String>[
  '/healthz',
  '/prices',
  '/analytics/model-metrics',
  '/analytics/feature-importance',
  '/analytics/yield-vs-rainfall',
  '/analytics/quantum-benchmark',
];

class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Dio get dio => _dio;

  bool get configured => Env.isApiConfigured;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.get<T>(path, queryParameters: queryParameters, options: options);

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Options? options,
  }) =>
      _dio.put<T>(path, data: data, options: options);

  Future<Response<T>> delete<T>(
    String path, {
    Options? options,
  }) =>
      _dio.delete<T>(path, options: options);

  /// Authenticated binary fetch (map layer PNGs need Bearer).
  Future<({List<int> bytes, String? geoBounds})> getBytes(String path) async {
    final resp = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return (bytes: resp.data ?? const <int>[], geoBounds: resp.headers.value('x-geo-bounds'));
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.isApiConfigured ? Env.apiV1Base : 'http://invalid.local',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
      headers: const {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.path;
        final isPublic = _publicSuffixes.any((s) => path == s || path.endsWith(s));
        if (!isPublic) {
          final token = ref.read(bearerTokenProvider);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (err, handler) async {
        final status = err.response?.statusCode ?? 0;
        final retryable = err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError ||
            status >= 500;
        final prior = err.requestOptions.extra['retryCount'] as int? ?? 0;
        if (retryable && prior < 2) {
          err.requestOptions.extra['retryCount'] = prior + 1;
          await Future<void>.delayed(Duration(milliseconds: 300 * (prior + 1)));
          try {
            final resp = await dio.fetch<dynamic>(err.requestOptions);
            return handler.resolve(resp);
          } catch (_) {
            // fall through
          }
        }
        handler.next(err);
      },
    ),
  );

  ref.onDispose(dio.close);
  return ApiClient(dio);
});
