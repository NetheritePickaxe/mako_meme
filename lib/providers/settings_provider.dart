import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  ThemeMode _themeMode = ThemeMode.system;
  int _presetIndex = 0;
  Color _customPrimary = const Color(0xFF6366F1);
  Color _customSecondary = const Color(0xFF6366F1);
  Color _customTertiary = const Color(0xFF6366F1);
  bool _useMonet = true;

  SettingsProvider(this._storage) {
    _themeMode = _toThemeMode(_storage.getSetting('themeMode'));
    final savedIndex = _storage.getSetting('presetIndex');
    if (savedIndex != null) {
      final idx = int.tryParse(savedIndex);
      if (idx != null && idx >= 0) {
        _presetIndex = idx;
      }
    } else {
      final savedHex = _storage.getSetting('accentColor');
      if (savedHex != null) {
        final parsed = int.tryParse(savedHex);
        if (parsed != null) {
          final match = AppTheme.presets.indexWhere(
            (p) => p.primary.toARGB32() == parsed,
          );
          if (match >= 0) {
            _presetIndex = match;
          }
        }
      }
    }
    _customPrimary = _parseColor(_storage.getSetting('customPrimary')) ?? const Color(0xFF6366F1);
    _customSecondary = _parseColor(_storage.getSetting('customSecondary')) ?? const Color(0xFF6366F1);
    _customTertiary = _parseColor(_storage.getSetting('customTertiary')) ?? const Color(0xFF6366F1);
    _useMonet = _storage.getSetting('useMonet') != 'false';
  }

  ThemeMode get themeMode => _themeMode;
  bool get useMonet => _useMonet;
  Color get customPrimary => _customPrimary;
  Color get customSecondary => _customSecondary;
  Color get customTertiary => _customTertiary;
  int get presetIndex => _presetIndex;

  ColorSchemePreset get currentPreset {
    if (_presetIndex < AppTheme.presets.length) {
      return AppTheme.presets[_presetIndex];
    }
    return const ColorSchemePreset(
      name: '自定义',
      primary: Color(0xFF6366F1),
      secondary: Color(0xFF6366F1),
      tertiary: Color(0xFF6366F1),
    );
  }

  Color get accentColor => currentPreset.primary;

  static ThemeMode _toThemeMode(String? v) {
    switch (v) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Color? _parseColor(String? s) {
    if (s == null) return null;
    final val = int.tryParse(s.replaceFirst('#', '0xFF'));
    return val != null ? Color(val) : null;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _storage.setSetting('themeMode', mode.name);
    notifyListeners();
  }

  Future<void> setUseMonet(bool v) async {
    _useMonet = v;
    await _storage.setSetting('useMonet', v.toString());
    notifyListeners();
  }

  Future<void> setPreset(int index) async {
    _presetIndex = index;
    _useMonet = false;
    await _storage.setSetting('presetIndex', index.toString());
    await _storage.setSetting('useMonet', 'false');
    notifyListeners();
  }

  Future<void> setCustomColors(Color primary, Color secondary, Color tertiary) async {
    _customPrimary = primary;
    _customSecondary = secondary;
    _customTertiary = tertiary;
    _presetIndex = AppTheme.presets.length;
    await _storage.setSetting('presetIndex', _presetIndex.toString());
    await _storage.setSetting('useMonet', 'false');
    await _storage.setSetting('customPrimary', '#${primary.toARGB32().toRadixString(16).padLeft(8, '0')}');
    await _storage.setSetting('customSecondary', '#${secondary.toARGB32().toRadixString(16).padLeft(8, '0')}');
    await _storage.setSetting('customTertiary', '#${tertiary.toARGB32().toRadixString(16).padLeft(8, '0')}');
    notifyListeners();
  }
}
