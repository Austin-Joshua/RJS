import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../i18n/translations.dart';

/// Simple, professional Material 3 themes (no glass / blur).
abstract final class AppTheme {
  static const double radiusSm = 12;
  static const double radiusMd = 16;

  static ThemeData light(LocaleCode locale) {
    final isTa = locale == tamil;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF047857),
      brightness: Brightness.light,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
    );
    final text = _textTheme(base.textTheme, isTa);
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    );
  }

  static ThemeData dark(LocaleCode locale) {
    final isTa = locale == tamil;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF34D399),
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
    );
    final text = _textTheme(base.textTheme, isTa);
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, bool isTa) {
    final body = GoogleFonts.notoSansTextTheme(base);
    return body.copyWith(
      headlineSmall: GoogleFonts.outfit(
        textStyle: body.headlineSmall,
        fontWeight: FontWeight.w600,
        letterSpacing: isTa ? 0.1 : -0.2,
      ),
      titleLarge: GoogleFonts.outfit(
        textStyle: body.titleLarge,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.outfit(
        textStyle: body.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      labelLarge: GoogleFonts.outfit(textStyle: body.labelLarge),
    );
  }
}
