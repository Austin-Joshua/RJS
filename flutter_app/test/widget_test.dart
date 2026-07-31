import 'package:flutter_app/core/env.dart';
import 'package:flutter_app/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo login details are wired for the seeded account', () {
    expect(Env.hasDemoLogin, isTrue);
    expect(Env.demoUserId, 'demo-farmer');
    expect(Env.devLoginToken, 't8DldZzFcIWlNyBluc0aOdyLaXFMel0J');
  });

  test('theme stays on the earthy palette', () {
    final theme = buildAppTheme();
    expect(theme.scaffoldBackgroundColor, AppColors.cream);
  });
}
