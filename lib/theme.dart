import 'package:flutter/material.dart';

/// Strata design system. Plus Jakarta Sans for display/headline, Inter for
/// everything else. Two seeds: ocean-blue (light), cyan (dark) — matches the
/// mockup palettes.
class SkyTheme {
  static const _lightSeed = Color(0xFF006495); // Primary
  static const _darkSeed = Color(0xFF00B4D8); // cyan accent family

  static ThemeData light() => _build(Brightness.light, _lightSeed);
  static ThemeData dark() => _build(Brightness.dark, _darkSeed);

  static ThemeData _build(Brightness b, Color seed) {
    final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final base = b == Brightness.light ? ThemeData.light() : ThemeData.dark();
    final text = base.textTheme.apply(fontFamily: 'Inter').copyWith(
          displayLarge: _h(base.textTheme.displayLarge),
          displayMedium: _h(base.textTheme.displayMedium),
          displaySmall: _h(base.textTheme.displaySmall),
          headlineLarge: _h(base.textTheme.headlineLarge),
          headlineMedium: _h(base.textTheme.headlineMedium),
          headlineSmall: _h(base.textTheme.headlineSmall),
          titleLarge: _h(base.textTheme.titleLarge, w: FontWeight.w700),
        );
    final scaffoldBg = b == Brightness.light
        ? const Color(0xFFF5F7FA)
        : const Color(0xFF0C1418);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: text,
      fontFamily: 'Inter',
      cardTheme: const CardThemeData(elevation: 0),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: cs.primaryContainer,
        selectedLabelTextStyle:
            TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
        selectedIconTheme: IconThemeData(color: cs.onPrimaryContainer),
        unselectedIconTheme:
            IconThemeData(color: cs.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }

  static TextStyle? _h(TextStyle? s, {FontWeight w = FontWeight.w800}) =>
      s?.copyWith(
          fontFamily: 'PlusJakartaSans', fontWeight: w, letterSpacing: -0.5);
}
