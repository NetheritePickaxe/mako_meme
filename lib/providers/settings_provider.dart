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
  
  // WebDAV 配置
  bool _useWebDav = false;
  String? _webDavBaseUrl;
  String? _webDavUsername;
  String? _webDavPassword;
  
  // 用户认证配置
  bool _useUserAuth = false;
  String? _currentUserId;
  Set<String> _adminUsers = {};

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
    
    // 加载 WebDAV 配置
    _useWebDav = _storage.getSetting('useWebDav') == 'true';
    _webDavBaseUrl = _storage.getSetting('webDavBaseUrl');
    _webDavUsername = _storage.getSetting('webDavUsername');
    _webDavPassword = _storage.getSetting('webDavPassword');
    
    // 加载用户认证配置
    _useUserAuth = _storage.getSetting('useUserAuth') == 'true';
    _currentUserId = _storage.getSetting('currentUserId');
    final adminStr = _storage.getSetting('adminUsers');
    if (adminStr != null && adminStr.isNotEmpty) {
      _adminUsers = adminStr.split(',').where((s) => s.isNotEmpty).toSet();
    }
  }

  // WebDAV getters
  bool get useWebDav => _useWebDav;
  String? get webDavBaseUrl => _webDavBaseUrl;
  String? get webDavUsername => _webDavUsername;
  String? get webDavPassword => _webDavPassword;
  
  // 用户认证 getters
  bool get useUserAuth => _useUserAuth;
  String? get currentUserId => _currentUserId;
  Set<String> get adminUsers => _adminUsers;
  bool isAdmin(String? userId) => userId != null && _adminUsers.contains(userId);

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
    return ColorSchemePreset(
      name: '自定义',
      primary: _customPrimary,
      secondary: _customSecondary,
      tertiary: _customTertiary,
      surfaceContainerHighest: null,
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
  
  // WebDAV 设置方法
  Future<void> setUseWebDav(bool v) async {
    _useWebDav = v;
    await _storage.setSetting('useWebDav', v.toString());
    notifyListeners();
  }
  
  Future<void> setWebDavConfig({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    _webDavBaseUrl = baseUrl;
    _webDavUsername = username;
    _webDavPassword = password;
    await _storage.setSetting('webDavBaseUrl', baseUrl);
    await _storage.setSetting('webDavUsername', username);
    await _storage.setSetting('webDavPassword', password);
    notifyListeners();
  }
  
  // 用户认证设置方法
  Future<void> setUseUserAuth(bool v) async {
    _useUserAuth = v;
    await _storage.setSetting('useUserAuth', v.toString());
    notifyListeners();
  }
  
  Future<void> setCurrentUserId(String? userId) async {
    _currentUserId = userId;
    await _storage.setSetting('currentUserId', userId ?? '');
    notifyListeners();
  }
  
  Future<void> setAdminUsers(Set<String> users) async {
    _adminUsers = users;
    await _storage.setSetting('adminUsers', users.join(','));
    notifyListeners();
  }
}
