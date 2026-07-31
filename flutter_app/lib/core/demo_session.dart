import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_token.dart';
import 'env.dart';

/// In-app demo session (seeded `demo-farmer` account). Separate from Clerk.
class DemoSessionNotifier extends Notifier<bool> {
  @override
  bool build() => Env.isDevLogin;

  void start() {
    final token = Env.devLoginToken;
    if (token.isEmpty) return;
    ref.read(bearerTokenProvider.notifier).setToken(token);
    state = true;
  }

  void end() {
    ref.read(bearerTokenProvider.notifier).setToken(null);
    state = false;
  }
}

final demoSessionProvider = NotifierProvider<DemoSessionNotifier, bool>(DemoSessionNotifier.new);
