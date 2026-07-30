import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

/// Stands in for the real home/dashboard screen until the rest of the app
/// (fields, plan, advisory — see TRD §10) is built.
class SignedInPlaceholder extends StatelessWidget {
  const SignedInPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FarmSync'),
        actions: const [Padding(padding: EdgeInsets.all(8), child: ClerkUserButton())],
      ),
      body: const Center(
        child: Text('Signed in. The rest of the app lands here next.'),
      ),
    );
  }
}
