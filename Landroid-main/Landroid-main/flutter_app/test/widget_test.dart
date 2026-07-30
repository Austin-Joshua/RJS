// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:landroid_flutter/src/api/client.dart';
import 'package:landroid_flutter/src/app.dart';

void main() {
  testWidgets('renders Landroid auth shell', (WidgetTester tester) async {
    await tester.pumpWidget(LandroidApp(apiClient: ApiClient()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Create account'), findsOneWidget);
  });
}
