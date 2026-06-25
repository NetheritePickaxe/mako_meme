import 'package:flutter/material.dart';

class ColorSchemePreset {
  final String name;
  final Color primary;

  const ColorSchemePreset({
    required this.name,
    required this.primary,
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
      name: '栖霞',
      primary: Color(0xFF7C3AED),
    ),
    ColorSchemePreset(
      name: '远帆',
      primary: Color(0xFF3B82F6),
    ),
    ColorSchemePreset(
      name: '薄桃',
      primary: Color(0xFFF472B6),
    ),
    ColorSchemePreset(
      name: '松风',
      primary: Color(0xFF059669),
    ),
    ColorSchemePreset(
      name: '秋暮',
      primary: Color(0xFFF97316),
    ),
    ColorSchemePreset(
      name: '沧渊',
      primary: Color(0xFF0EA5E9),
    ),
    ColorSchemePreset(
      name: '月白',
      primary: Color(0xFF6B7280),
    ),
    ColorSchemePreset(
      name: '山吹',
      primary: Color(0xFF16A34A),
    ),
    ColorSchemePreset(
      name: '紫苑',
      primary: Color(0xFF8B5CF6),
    ),
    ColorSchemePreset(
      name: '花火',
      primary: Color(0xFFFF6B9D),
    ),
    ColorSchemePreset(
      name: '下流忍者',
      primary: Color(0xFF8D4658),
    ),
    ColorSchemePreset(
      name: '巫女大人',
      primary: Color(0xFFA83A47),
    ),
    ColorSchemePreset(
      name: '幼刀丛雨',
      primary: Color(0xFFA83C4C),
    ),
    ColorSchemePreset(
      name: '世界之大',
      primary: Color(0xFF6B77A9),
    ),
    ColorSchemePreset(
      name: '田心屋',
      primary: Color(0xFFD97706),
    ),
  ];

  static ThemeData light(Color seed) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  static ThemeData lightWithPreset(ColorSchemePreset p) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(seedColor: p.primary, brightness: Brightness.light),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  static ThemeData darkWithPreset(ColorSchemePreset p) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: p.primary, brightness: Brightness.dark),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
