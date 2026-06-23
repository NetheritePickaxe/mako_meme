import 'package:flutter/material.dart';

class ColorSchemePreset {
  final String name;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  const ColorSchemePreset({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.tertiary,
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
      secondary: Color(0xFF06B6D4),
      tertiary: Color(0xFFEC4899),
    ),
    ColorSchemePreset(
      name: '远帆',
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF22D3EE),
      tertiary: Color(0xFF6366F1),
    ),
    ColorSchemePreset(
      name: '薄桃',
      primary: Color(0xFFF472B6),
      secondary: Color(0xFFFB923C),
      tertiary: Color(0xFFA78BFA),
    ),
    ColorSchemePreset(
      name: '松风',
      primary: Color(0xFF059669),
      secondary: Color(0xFF10B981),
      tertiary: Color(0xFF65A30D),
    ),
    ColorSchemePreset(
      name: '秋暮',
      primary: Color(0xFFF97316),
      secondary: Color(0xFFEF4444),
      tertiary: Color(0xFFF59E0B),
    ),
    ColorSchemePreset(
      name: '沧渊',
      primary: Color(0xFF0EA5E9),
      secondary: Color(0xFF14B8A6),
      tertiary: Color(0xFF3B82F6),
    ),
    ColorSchemePreset(
      name: '月白',
      primary: Color(0xFF6B7280),
      secondary: Color(0xFF9CA3AF),
      tertiary: Color(0xFF4B5563),
    ),
    ColorSchemePreset(
      name: '山吹',
      primary: Color(0xFF16A34A),
      secondary: Color(0xFF65A30D),
      tertiary: Color(0xFFD97706),
    ),
    ColorSchemePreset(
      name: '紫苑',
      primary: Color(0xFF8B5CF6),
      secondary: Color(0xFFD946EF),
      tertiary: Color(0xFF6366F1),
    ),
    ColorSchemePreset(
      name: '花火',
      primary: Color(0xFFFF6B9D),
      secondary: Color(0xFFFFD93D),
      tertiary: Color(0xFF6BCB77),
    ),
    ColorSchemePreset(
      name: '下流忍者',
      primary: Color(0xFF8D4658),
      secondary: Color(0xFF51444C),
      tertiary: Color(0xFF3E3C50),
    ),
    ColorSchemePreset(
      name: '巫女大人',
      primary: Color(0xFFA83A47),
      secondary: Color(0xFFCD5A5D),
      tertiary: Color(0xFFDFD0D7),
    ),
    ColorSchemePreset(
      name: '幼刀丛雨',
      primary: Color(0xFFA83C4C),
      secondary: Color(0xFF57455D),
      tertiary: Color(0xFFBFB59E),
    ),
    ColorSchemePreset(
      name: '世界之大',
      primary: Color(0xFF6B77A9),
      secondary: Color(0xFF51547E),
      tertiary: Color(0xFFFFF0CF),
    ),
    ColorSchemePreset(
      name: '田心屋',
      primary: Color(0xFFD97706),
      secondary: Color(0xFFDC2626),
      tertiary: Color(0xFFF59E0B),
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
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.primary,
      secondary: p.secondary,
      tertiary: p.tertiary,
      brightness: Brightness.light,
    ),
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
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.primary,
      secondary: p.secondary,
      tertiary: p.tertiary,
      brightness: Brightness.dark,
    ),
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
