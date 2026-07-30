import 'package:flutter_app/features/app/farmsync_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows sign-in with demo farmer when Clerk key is configured', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FarmSyncApp()));
    await tester.pump(); // ClerkAuth may schedule async init
    expect(find.textContaining('Continue as Demo Farmer'), findsWidgets);
  });
}
