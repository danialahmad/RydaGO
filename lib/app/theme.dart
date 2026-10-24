import 'package:flutter/material.dart';

/// Colours used across the app. Light, friendly and high-contrast, in the spirit
/// of a driving app: big touch targets, bold type, one bright accent.
/// (Own palette and Material icons only: no third-party logos or mascots.)
class AppColors {
  AppColors._();

  static const brand = Color(0xFF2DB7F5); // route line, active states, links
  static const brandDeep = Color(0xFF1597D6); // text/buttons on light backgrounds
  static const go = Color(0xFF2FBF71); // "Mula", arrival, success
  static const report = Color(0xFFFF7A1A); // the report button
  static const danger = Color(0xFFE5484D); // stop, destination, errors
  static const ink = Color(0xFF0E1A2B); // main text on light
  static const muted = Color(0xFF6B7A8C); // secondary text on light
  static const banner = Color(0xFF0B1220); // turn banner background
  static const surfaceDark = Color(0xFF16222F); // sheets in dark mode
  static const line = Color(0xFFE3E9F0); // dividers on light
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
  ).copyWith(
    primary: dark ? AppColors.brand : AppColors.brandDeep,
    surface: dark ? AppColors.surfaceDark : Colors.white,
    onSurface: dark ? Colors.white : AppColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0E1822) : const Color(0xFFF4F7FA),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          color: scheme.onSurface, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
      labelLarge: TextStyle(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1E2D3D) : const Color(0xFFEDF2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
        color: dark ? const Color(0xFF243546) : AppColors.line, space: 1),
  );
}
