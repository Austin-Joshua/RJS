import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_token.dart';

/// Offline pitch path: skip Clerk and open [HomeShell] as the demo farmer.
class DemoSessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() {
    state = true;
    ref.read(bearerTokenProvider.notifier).setToken('demo-farmer');
  }

  void exit() {
    state = false;
    ref.read(bearerTokenProvider.notifier).setToken(null);
  }
}

final demoSessionProvider = NotifierProvider<DemoSessionNotifier, bool>(DemoSessionNotifier.new);
