import 'package:flutter/material.dart';

/// Minimalist, Claude/Grok-style theme: warm neutral surfaces, a single
/// restrained accent, no elevation or tint. Light and dark follow the system.
class AppTheme {
  /// The one accent colour, used sparingly (send button, links, focus).
  static const _accentLight = Color(0xFFB65C3A);
  static const _accentDark = Color(0xFFD2764F);

  /// Fallback schemes for devices without Material You dynamic colour.
  static ThemeData light() => themeFrom(_lightScheme());
  static ThemeData dark() => themeFrom(_darkScheme());

  static ColorScheme _lightScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: _accentLight,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    return base.copyWith(
      primary: _accentLight,
      onPrimary: Colors.white,
      surface: const Color(0xFFF7F6F3),
      onSurface: const Color(0xFF23211E),
      onSurfaceVariant: const Color(0xFF6B6862),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF2F1ED),
      surfaceContainer: const Color(0xFFECEBE5),
      surfaceContainerHigh: const Color(0xFFE7E5DF),
      surfaceContainerHighest: const Color(0xFFE1DFD8),
      outline: const Color(0xFFB7B3A9),
      outlineVariant: const Color(0xFFE4E1D9),
    );
  }

  static ColorScheme _darkScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: _accentDark,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    return base.copyWith(
      primary: _accentDark,
      onPrimary: const Color(0xFF33190E),
      surface: const Color(0xFF1E1E1C),
      onSurface: const Color(0xFFECEAE3),
      onSurfaceVariant: const Color(0xFFA9A69E),
      surfaceContainerLowest: const Color(0xFF181816),
      surfaceContainerLow: const Color(0xFF232320),
      surfaceContainer: const Color(0xFF272724),
      surfaceContainerHigh: const Color(0xFF302F2B),
      surfaceContainerHighest: const Color(0xFF3A3934),
      outline: const Color(0xFF57554F),
      outlineVariant: const Color(0xFF33322E),
    );
  }

  /// Applies the minimalist styling on top of any [scheme] — the system's
  /// Material You palette when available, or a fallback neutral scheme.
  static ThemeData themeFrom(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    // Slightly airier body text for comfortable long-form reading.
    final text = base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
