import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  ThemeMode _themeMode = ThemeMode.system;
  int _accentColorHex = 0xFF6366F1;
  bool _useMonet = true;

  SettingsProvider(this._storage) {
    _themeMode = _toThemeMode(_storage.getSetting('themeMode'));
    final saved = _storage.getSetting('accentColor');
    _accentColorHex = saved != null ? int.tryParse(saved) ?? 0xFF6366F1 : 0xFF6366F1;
    _useMonet = _storage.getSetting('useMonet') != 'false';
  }

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => Color(_accentColorHex);
  bool get useMonet => _useMonet;

  static ThemeMode _toThemeMode(String? v) {
    switch (v) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
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

  Future<void> setAccentColor(int hex) async {
    _accentColorHex = hex;
    _useMonet = false;
    await _storage.setSetting('accentColor', '0x${hex.toRadixString(16)}');
    await _storage.setSetting('useMonet', 'false');
    notifyListeners();
  }
}
