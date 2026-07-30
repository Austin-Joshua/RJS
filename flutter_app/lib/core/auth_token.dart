import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mutable bearer token used by [ApiClient]. Demo mode sets `demo-farmer`;
/// Clerk signed-in path sets the session JWT.
class BearerTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setToken(String? token) => state = token;
}

final bearerTokenProvider = NotifierProvider<BearerTokenNotifier, String?>(BearerTokenNotifier.new);
