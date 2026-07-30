import 'package:flutter/material.dart';

/// Earthy palette (deep greens, terracotta, soil browns) per project UI/UX
/// guidance — shared across every screen, not just auth.
class AppColors {
  const AppColors._();

  static const deepGreen = Color(0xFF2E4A34);
  static const terracotta = Color(0xFFC1592A);
  static const soilBrown = Color(0xFF4A3527);
  static const cream = Color(0xFFF7F1E6);
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.deepGreen,
    primary: AppColors.deepGreen,
    secondary: AppColors.terracotta,
    surface: AppColors.cream,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.deepGreen,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
  );
}
