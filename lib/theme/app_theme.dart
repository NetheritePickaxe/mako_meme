import 'package:flutter/material.dart';

class ColorSchemePreset {
  final String name;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color? surfaceContainerHighest;

  const ColorSchemePreset({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    this.surfaceContainerHighest,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorSchemePreset &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class AppTheme {
  static const primary = Color(0xFF6366F1);

  static const presets = <ColorSchemePreset>[
    ColorSchemePreset(
      name: '巫女大人',
      primary: Color(0xFFfbfbfe),
      secondary: Color(0xFFffb7cd),
      tertiary: Color(0xFF80bce7),
    ),
    ColorSchemePreset(
      name: '下流忍者',
      primary: Color(0xFFb8b3e5),
      secondary: Color(0xFFb7e5a1),
      tertiary: Color(0xFFee6256),
    ),
    ColorSchemePreset(
      name: '幼刀丛雨',
      primary: Color(0xFFbcd5aa),
      secondary: Color(0xFF7a55a8),
      tertiary: Color(0xFFff3e62),
    ),
    ColorSchemePreset(
      name: '世界之大',
      primary: Color(0xFFfcf06b),
      secondary: Color(0xFF5a74bd),
      tertiary: Color(0xFFcb7bc8),
    ),
    ColorSchemePreset(
      name: '田心屋',
      primary: Color(0xFFffb1b5),
      secondary: Color(0xFFc7738c),
      tertiary: Color(0xFFfdffc9),
    ),
    ColorSchemePreset(
      name: '森人板卡',
      primary: Color(0xFF9cd7e2),
      secondary: Color(0xFFF19eb6),
      tertiary: Color(0xFFc78dbd),
    ),
  ];

  static Color _onColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }

  static ThemeData light(Color seed) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
    fontFamily: 'Noto Sans SC',
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );

  static ThemeData dark(Color seed) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
    fontFamily: 'Noto Sans SC',
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade900,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );

  static ThemeData lightWithPreset(ColorSchemePreset p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: Brightness.light,
    ).copyWith(
      secondary: p.secondary,
      onSecondary: _onColor(p.secondary),
      secondaryContainer: p.secondary.withValues(alpha: 0.15),
      tertiary: p.tertiary,
      onTertiary: _onColor(p.tertiary),
      tertiaryContainer: p.tertiary.withValues(alpha: 0.15),
      surfaceContainerHighest: p.surfaceContainerHighest,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: 'Noto Sans SC',
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  static ThemeData darkWithPreset(ColorSchemePreset p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: Brightness.dark,
    ).copyWith(
      secondary: p.secondary,
      onSecondary: _onColor(p.secondary),
      secondaryContainer: p.secondary.withValues(alpha: 0.2),
      tertiary: p.tertiary,
      onTertiary: _onColor(p.tertiary),
      tertiaryContainer: p.tertiary.withValues(alpha: 0.2),
      surfaceContainerHighest: p.surfaceContainerHighest,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: 'Noto Sans SC',
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade900,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
