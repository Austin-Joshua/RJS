import 'package:flutter/material.dart';

/// Earthy palette — deep crop greens, soil/clay browns, warm terracotta.
/// No generic Material blues.
class AppColors {
  const AppColors._();

  static const deepGreen = Color(0xFF2E4A34);
  static const terracotta = Color(0xFFC1592A);
  static const soilBrown = Color(0xFF4A3527);
  static const cream = Color(0xFFF7F1E6);
  static const clay = Color(0xFF8B6F47);
}

ThemeData buildAppTheme() {
  const textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.soilBrown, height: 1.2),
    displayMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.soilBrown, height: 1.2),
    headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.deepGreen, height: 1.25),
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.deepGreen, height: 1.3),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.soilBrown, height: 1.3),
    titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.soilBrown, height: 1.35),
    bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: AppColors.soilBrown, height: 1.45),
    bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.soilBrown, height: 1.45),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.deepGreen, height: 1.3),
  );

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.deepGreen,
    primary: AppColors.deepGreen,
    secondary: AppColors.terracotta,
    surface: AppColors.cream,
    error: AppColors.terracotta,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.deepGreen,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.deepGreen,
      inactiveTrackColor: AppColors.clay.withValues(alpha: 0.35),
      thumbColor: AppColors.terracotta,
      overlayColor: AppColors.terracotta.withValues(alpha: 0.16),
      valueIndicatorColor: AppColors.deepGreen,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cream,
      indicatorColor: AppColors.deepGreen.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 28,
          color: states.contains(WidgetState.selected) ? AppColors.deepGreen : AppColors.soilBrown,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 14,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? AppColors.deepGreen : AppColors.soilBrown,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
