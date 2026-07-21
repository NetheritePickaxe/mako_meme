import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 主题预设 — Material 3 单种子色方案。
///
/// M3 的 ColorScheme.fromSeed 会从一个种子色自动派生出完整的 30+ 色角色
/// （primary / onPrimary / primaryContainer / secondary / tertiary / surface 系列等），
/// 保证整个色板在感知上和谐统一。因此预设只需要一个种子色即可。
class ColorSchemePreset {
  final String name;
  final Color seed;

  const ColorSchemePreset({required this.name, required this.seed});

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
  /// 默认种子色（与图标启动器保持一致）
  static const Color defaultSeed = Color(0xFF6366F1);

  /// 预设种子色板
  /// 顺序：5 个主题配色（用户自定义）→ 靛蓝 → 其他自然命名配色
  static const presets = <ColorSchemePreset>[
    // 用户自定义主题配色（置顶）
    ColorSchemePreset(name: '巫女大人', seed: Color(0xFFFBFBFE)),
    ColorSchemePreset(name: '下流忍者', seed: Color(0xFFB8B3E5)),
    ColorSchemePreset(name: '幼刀丛雨', seed: Color(0xFFBCD5AA)),
    ColorSchemePreset(name: '世界之大', seed: Color(0xFFFCF06B)),
    ColorSchemePreset(name: '田心屋', seed: Color(0xFFFFB1B5)),
    ColorSchemePreset(name: '靛蓝', seed: Color(0xFF6366F1)),
    // 其他自然命名配色
    ColorSchemePreset(name: '林荫', seed: Color(0xFF2E7D32)),
    ColorSchemePreset(name: '琥珀', seed: Color(0xFF8D6E63)),
    ColorSchemePreset(name: '潮汐', seed: Color(0xFF1565C0)),
    ColorSchemePreset(name: '星云', seed: Color(0xFF7B1FA2)),
    ColorSchemePreset(name: '暮霞', seed: Color(0xFFEF6C00)),
  ];

  /// 生成 M3 ColorScheme。
  /// [seed] 种子色；[brightness] 明暗；[pureBlack] 仅暗色：是否使用纯黑背景。
  static ColorScheme _scheme(Color seed, Brightness brightness, {bool pureBlack = false}) {
    var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    if (brightness == Brightness.dark && pureBlack) {
      // 纯黑模式：所有 surface 系列强制为黑色/近黑，与普通深色明显区分
      scheme = scheme.copyWith(
        surface: Colors.black,
        onSurface: Colors.grey.shade50,
        onSurfaceVariant: Colors.grey.shade400,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF050505),
        surfaceContainer: const Color(0xFF0D0D0D),
        surfaceContainerHigh: const Color(0xFF141414),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
        inverseSurface: Colors.grey.shade100,
        onInverseSurface: Colors.black,
        scrim: Colors.black,
        shadow: Colors.black.withValues(alpha: 0.75),
      );
    }
    return scheme;
  }

  /// 通用 M3 组件主题。
  ///
  /// 把所有组件主题集中在这里，避免 light/dark/preset 各分支重复定义。
  static ThemeData _build(ColorScheme scheme, {bool pureBlack = false}) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pureBlack && isDark ? Colors.black : null,
      fontFamily: 'Noto Sans SC',
      // 启用预测式返回页面切换动画（Android 14+）
      // 配合 AndroidManifest 中 android:enableOnBackInvokedCallback="true"
      // 用户从屏幕左/右边缘滑动时可以看到目标页面跟随手势滑入
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: pureBlack && isDark ? Colors.black : null,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? (pureBlack ? const Color(0xFF1C1C1C) : Colors.grey.shade900)
            : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      drawerTheme: isDark && pureBlack
          ? const DrawerThemeData(backgroundColor: Colors.black)
          : null,
      navigationBarTheme: isDark && pureBlack
          ? NavigationBarThemeData(backgroundColor: Colors.black)
          : null,
      bottomAppBarTheme: isDark && pureBlack
          ? const BottomAppBarThemeData(color: Colors.black)
          : null,
      // 让 FAB / Chip / 按钮 / 对话框 / 导航栏 统一走 M3 默认 + 圆角
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: const ChipThemeData(
        shape: StadiumBorder(),
      ),
      buttonTheme: const ButtonThemeData(
        shape: StadiumBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  /// 浅色主题（动态颜色或预设/自定义种子）
  static ThemeData light(Color seed) =>
      _build(_scheme(seed, Brightness.light));

  /// 暗色主题（动态颜色或预设/自定义种子）
  static ThemeData dark(Color seed, {bool pureBlack = false}) =>
      _build(_scheme(seed, Brightness.dark, pureBlack: pureBlack), pureBlack: pureBlack);
}
