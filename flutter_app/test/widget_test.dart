import 'package:flutter_app/features/app/farmsync_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows setup message when CLERK_PUBLISHABLE_KEY is unset', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FarmSyncApp()));
    expect(find.textContaining('Missing CLERK_PUBLISHABLE_KEY'), findsOneWidget);
    expect(find.text('Continue as Demo Farmer'), findsOneWidget);
  });
}
