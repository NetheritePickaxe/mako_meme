import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  ThemeMode _themeMode = ThemeMode.system;
  int _presetIndex = 0;
  Color _customSeed = AppTheme.defaultSeed;
  bool _useMonet = true;
  bool _pureBlack = false;
  int _gridColumns = 0; // 0 = 自动
  bool _autoClassify = true; // 导入时按画幅自动归类
  double _classifyRatio = 1.1; // 宽高比阈值，<=此值视为正方形(表情)

  // WebDAV 配置
  bool _useWebDav = false;
  String? _webDavBaseUrl;
  String? _webDavUsername;
  String? _webDavPassword;

  // 存储位置
  String _storageLocation = 'app'; // 'app' 或 'custom'
  String? _customStoragePath;

  SettingsProvider(this._storage) {
    _themeMode = _toThemeMode(_storage.getSetting('themeMode'));
    final savedIndex = _storage.getSetting('presetIndex');
    if (savedIndex != null) {
      final idx = int.tryParse(savedIndex);
      if (idx != null && idx >= 0) {
        _presetIndex = idx;
      }
    } else {
      // 兼容旧版 accentColor：尝试匹配预设种子色
      final savedHex = _storage.getSetting('accentColor');
      if (savedHex != null) {
        final parsed = int.tryParse(savedHex);
        if (parsed != null) {
          final match = AppTheme.presets.indexWhere(
            (p) => p.seed.toARGB32() == parsed,
          );
          if (match >= 0) {
            _presetIndex = match;
          }
        }
      }
    }
    // 兼容旧版 customPrimary（旧自定义三色），新版只用 customSeed
    _customSeed = _parseColor(_storage.getSetting('customSeed')) ??
        _parseColor(_storage.getSetting('customPrimary')) ??
        AppTheme.defaultSeed;
    _useMonet = _storage.getSetting('useMonet') != 'false';
    _pureBlack = _storage.getSetting('pureBlack') == 'true';
    final savedCols = int.tryParse(_storage.getSetting('gridColumns') ?? '');
    if (savedCols != null && savedCols >= 0 && savedCols <= 10) _gridColumns = savedCols;
    _autoClassify = _storage.getSetting('autoClassify') != 'false';
    final savedRatio = double.tryParse(_storage.getSetting('classifyRatio') ?? '');
    if (savedRatio != null && savedRatio > 0.5 && savedRatio < 3.0) _classifyRatio = savedRatio;

    // 加载 WebDAV 配置
    _useWebDav = _storage.getSetting('useWebDav') == 'true';
    _webDavBaseUrl = _storage.getSetting('webDavBaseUrl');
    _webDavUsername = _storage.getSetting('webDavUsername');
    _webDavPassword = _storage.getSetting('webDavPassword');

    // 加载存储位置配置
    _storageLocation = _storage.getSetting('storageLocation') ?? 'app';
    _customStoragePath = _storage.getSetting('customStoragePath');
  }

  // WebDAV getters
  bool get useWebDav => _useWebDav;
  String? get webDavBaseUrl => _webDavBaseUrl;
  String? get webDavUsername => _webDavUsername;
  String? get webDavPassword => _webDavPassword;

  // 存储位置 getters
  String get storageLocation => _storageLocation;
  String? get customStoragePath => _customStoragePath;

  ThemeMode get themeMode => _themeMode;
  bool get useMonet => _useMonet;
  bool get pureBlack => _pureBlack;
  int get gridColumns => _gridColumns;
  bool get autoClassify => _autoClassify;
  double get classifyRatio => _classifyRatio;
  Color get customSeed => _customSeed;
  int get presetIndex => _presetIndex;

  /// 当前生效的预设。若为自定义则返回基于 [_customSeed] 的预设。
  ColorSchemePreset get currentPreset {
    if (_presetIndex < AppTheme.presets.length) {
      return AppTheme.presets[_presetIndex];
    }
    return ColorSchemePreset(name: '自定义', seed: _customSeed);
  }

  /// 当前生效的种子色（用于动态颜色 / 主题构建）
  Color get seedColor => currentPreset.seed;

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

  Future<void> setPureBlack(bool v) async {
    _pureBlack = v;
    await _storage.setSetting('pureBlack', v.toString());
    notifyListeners();
  }

  Future<void> setGridColumns(int v) async {
    _gridColumns = v;
    await _storage.setSetting('gridColumns', v.toString());
    notifyListeners();
  }

  Future<void> setAutoClassify(bool v) async {
    _autoClassify = v;
    await _storage.setSetting('autoClassify', v.toString());
    notifyListeners();
  }

  Future<void> setClassifyRatio(double v) async {
    if (v < 0.5 || v > 3.0) return;
    _classifyRatio = v;
    await _storage.setSetting('classifyRatio', v.toString());
    notifyListeners();
  }

  Future<void> setPreset(int index) async {
    _presetIndex = index;
    _useMonet = false;
    await _storage.setSetting('presetIndex', index.toString());
    await _storage.setSetting('useMonet', 'false');
    notifyListeners();
  }

  /// 设置自定义种子色。M3 会从这个种子派生整套色板。
  Future<void> setCustomSeed(Color seed) async {
    _customSeed = seed;
    _presetIndex = AppTheme.presets.length;
    await _storage.setSetting('presetIndex', _presetIndex.toString());
    await _storage.setSetting('useMonet', 'false');
    await _storage.setSetting('customSeed', '#${seed.toARGB32().toRadixString(16).padLeft(8, '0')}');
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

  // 存储位置设置方法
  Future<void> setStorageLocation(String location) async {
    _storageLocation = location;
    await _storage.setSetting('storageLocation', location);
    notifyListeners();
  }

  Future<void> setCustomStoragePath(String? path) async {
    _customStoragePath = path;
    await _storage.setSetting('customStoragePath', path ?? '');
    notifyListeners();
  }
}
