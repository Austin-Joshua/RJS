import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_token.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/repos/sync_worker.dart';
import '../auth/demo_session.dart';
import '../auth/sign_in_page.dart';
import '../home/home_shell.dart';

class FarmSyncApp extends ConsumerWidget {
  const FarmSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoSessionProvider);

    // Demo farmer bypass — no Clerk round-trip required for the pitch path.
    if (demo) {
      return MaterialApp(
        title: 'FarmSync',
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: const _BootstrappedHome(),
      );
    }

    if (!Env.isClerkConfigured) {
      return MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: const _MissingClerkKeyScreen(),
      );
    }

    return ClerkAuth(
      config: ClerkAuthConfig(publishableKey: Env.clerkPublishableKey),
      child: MaterialApp(
        title: 'FarmSync',
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: ClerkErrorListener(
          child: ClerkAuthBuilder(
            signedInBuilder: (context, authState) => const _ClerkTokenBinder(child: _BootstrappedHome()),
            signedOutBuilder: (context, authState) => const SignInPage(),
          ),
        ),
      ),
    );
  }
}

/// Pulls Clerk session JWT into [bearerTokenProvider] for FastAPI.
class _ClerkTokenBinder extends ConsumerStatefulWidget {
  const _ClerkTokenBinder({required this.child});

  final Widget child;

  @override
  ConsumerState<_ClerkTokenBinder> createState() => _ClerkTokenBinderState();
}

class _ClerkTokenBinderState extends ConsumerState<_ClerkTokenBinder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final auth = ClerkAuth.of(context, listen: false);
      final token = await auth.sessionToken();
      if (mounted) ref.read(bearerTokenProvider.notifier).setToken(token.jwt);
    } catch (_) {
      // Demo/API can still run with a missing Clerk token if using demo bearer.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BootstrappedHome extends ConsumerStatefulWidget {
  const _BootstrappedHome();

  @override
  ConsumerState<_BootstrappedHome> createState() => _BootstrappedHomeState();
}

class _BootstrappedHomeState extends ConsumerState<_BootstrappedHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(syncWorkerProvider).flush();
    });
  }

  @override
  Widget build(BuildContext context) => const HomeShell();
}

class _MissingClerkKeyScreen extends ConsumerWidget {
  const _MissingClerkKeyScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Missing CLERK_PUBLISHABLE_KEY.\n\n'
                'Use demo mode, or run with:\n'
                'flutter run --dart-define=CLERK_PUBLISHABLE_KEY=pk_...\n'
                '--dart-define=API_BASE_URL=https://your-app.up.railway.app',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => ref.read(demoSessionProvider.notifier).enter(),
                child: const Text('Continue as Demo Farmer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
