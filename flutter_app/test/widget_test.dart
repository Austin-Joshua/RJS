import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/main.dart';

void main() {
  testWidgets('shows setup message when CLERK_PUBLISHABLE_KEY is unset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FarmSyncApp());
    expect(find.textContaining('Missing CLERK_PUBLISHABLE_KEY'), findsOneWidget);
  });
}
