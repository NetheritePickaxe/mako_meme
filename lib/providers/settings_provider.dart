import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/ime_status_service.dart';
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
  bool _landscapePreview = false; // 横屏模式：左侧大图预览

  // 卡片显示选项
  bool _showCardName = false;
  bool _showCardTags = false;
  bool _showCardType = false;
  bool _showCardExt = false;

  // 自定义主界面背景
  String? _bgImagePath; // meme 的相对存储路径
  double _bgBlur = 0.0; // 高斯模糊半径
  double _bgOpacity = 0.0; // 暗色遮罩透明度（0~1，保证内容可读）

  // 手机端长按行为：'share' 或 'menu'
  String _mobileLongPress = 'share';

  // tag 细分：开启后大图详情面板显示双列 tag（情绪+普通）
  bool _tagSubdivision = false;

  // 分类可见性 — 默认仅显示 emoji/gif/image/text 四类
  // 其他（manga/vector/psd/pdf/portrait/cg/character_card/novel）默认隐藏，可在设置中开启
  // 存储为逗号分隔的隐藏类型字符串
  Set<String> _hiddenCategories = {
    'manga', 'vector', 'psd', 'pdf',
    'portrait', 'cg', 'character_card', 'novel',
  };

  // 用户自定义分类（纯标签，无特殊功能）
  List<String> _customCategories = [];

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
    _landscapePreview = _storage.getSetting('landscapePreview') == 'true';

    // 加载卡片显示选项
    _showCardName = _storage.getSetting('showCardName') == 'true';
    _showCardTags = _storage.getSetting('showCardTags') == 'true';
    _showCardType = _storage.getSetting('showCardType') == 'true';
    _showCardExt = _storage.getSetting('showCardExt') == 'true';

    // 加载自定义背景
    _bgImagePath = _storage.getSetting('bgImagePath');
    if (_bgImagePath == '') _bgImagePath = null;
    final savedBlur = double.tryParse(_storage.getSetting('bgBlur') ?? '');
    if (savedBlur != null && savedBlur >= 0 && savedBlur <= 50) _bgBlur = savedBlur;
    final savedOpacity = double.tryParse(_storage.getSetting('bgOpacity') ?? '');
    if (savedOpacity != null && savedOpacity >= 0 && savedOpacity <= 1) _bgOpacity = savedOpacity;

    // 加载手机端长按行为
    final savedLongPress = _storage.getSetting('mobileLongPress');
    if (savedLongPress == 'menu' || savedLongPress == 'share') {
      _mobileLongPress = savedLongPress!;
    }

    // 加载 tag 细分设置
    _tagSubdivision = _storage.getSetting('tagSubdivision') == 'true';

    // 加载分类可见性（未设置时默认仅显示 emoji/gif/image/text）
    final savedHidden = _storage.getSetting('hiddenCategories');
    if (savedHidden != null && savedHidden.isNotEmpty) {
      _hiddenCategories = savedHidden.split(',').where((s) => s.isNotEmpty).toSet();
    }
    // 加载自定义分类
    final savedCustom = _storage.getSetting('customCategories');
    if (savedCustom != null && savedCustom.isNotEmpty) {
      _customCategories = savedCustom.split(',').where((s) => s.isNotEmpty).toList();
    }

    // 加载 WebDAV 配置
    _useWebDav = _storage.getSetting('useWebDav') == 'true';
    _webDavBaseUrl = _storage.getSetting('webDavBaseUrl');
    _webDavUsername = _storage.getSetting('webDavUsername');
    _webDavPassword = _storage.getSetting('webDavPassword');

    // 加载存储位置配置
    _storageLocation = _storage.getSetting('storageLocation') ?? 'app';
    _customStoragePath = _storage.getSetting('customStoragePath');

    // 初始同步 IME 主题配色
    _syncImeTheme();
  }

  /// 将当前主题配色同步到 IME 服务（仅 Android）。
  /// IME 读取 filesDir/ime_theme.json 应用配色。
  void _syncImeTheme() {
    if (kIsWeb || !Platform.isAndroid) return;
    // 判断当前是否为深色模式（system 模式按系统值）
    final isDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    // 语义化色板：bg/surface/cardBg/keyBg/keyFuncBg 等按键专用色，
    // 让 IME 端按键 / 网格 / Tab 各部位有独立语义色，参考 Gboard 配色规范。
    final bg = isDark ? 0xFF161616 : 0xFFF0F0F3;
    final surface = isDark ? 0xFF1F1F1F : 0xFFE6E6EA;
    final cardBg = isDark ? 0xFF242424 : 0xFFFFFFFF;
    final keyBg = isDark ? scheme.surfaceContainerHighest : scheme.surface;
    final keyFuncBg = isDark ? scheme.surfaceContainer : scheme.surfaceContainerHighest;
    final divider = isDark ? 0xFF2E2E2E : 0xFFDADADA;
    final json = '{'
        '"dark":$isDark,'
        '"bg":$bg,'
        '"surface":$surface,'
        '"cardBg":$cardBg,'
        '"keyBg":${keyBg.toARGB32()},'
        '"keyActiveBg":${scheme.primary.toARGB32()},'
        '"keyFuncBg":${keyFuncBg.toARGB32()},'
        '"accent":${scheme.primary.toARGB32()},'
        '"onAccent":${scheme.onPrimary.toARGB32()},'
        '"text":${(isDark ? 0xFFEEEEEE : 0xFF222222)},'
        '"subText":${(isDark ? 0xFF9A9A9A : 0xFF666666)},'
        '"tabBg":${scheme.primary.toARGB32()},'
        '"tabText":${scheme.onPrimary.toARGB32()},'
        '"divider":$divider'
        '}';
    ImeStatusService.updateImeTheme(json);
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
  bool get landscapePreview => _landscapePreview;
  bool get showCardName => _showCardName;
  bool get showCardTags => _showCardTags;
  bool get showCardType => _showCardType;
  bool get showCardExt => _showCardExt;

  String? get bgImagePath => _bgImagePath;
  double get bgBlur => _bgBlur;
  double get bgOpacity => _bgOpacity;
  bool get hasCustomBg => _bgImagePath != null && _bgImagePath!.isNotEmpty;
  String get mobileLongPress => _mobileLongPress;
  bool get mobileLongPressIsMenu => _mobileLongPress == 'menu';

  bool get tagSubdivision => _tagSubdivision;

  Set<String> get hiddenCategories => Set.unmodifiable(_hiddenCategories);
  List<String> get customCategories => List.unmodifiable(_customCategories);

  /// 判断某分类是否在主界面分类栏中可见
  bool isCategoryVisible(String type) => !_hiddenCategories.contains(type);
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
    _syncImeTheme();
    notifyListeners();
  }

  Future<void> setUseMonet(bool v) async {
    _useMonet = v;
    await _storage.setSetting('useMonet', v.toString());
    _syncImeTheme();
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

  Future<void> setLandscapePreview(bool v) async {
    _landscapePreview = v;
    await _storage.setSetting('landscapePreview', v.toString());
    notifyListeners();
  }

  Future<void> setShowCardName(bool v) async {
    _showCardName = v;
    await _storage.setSetting('showCardName', v.toString());
    notifyListeners();
  }

  Future<void> setShowCardTags(bool v) async {
    _showCardTags = v;
    await _storage.setSetting('showCardTags', v.toString());
    notifyListeners();
  }

  Future<void> setShowCardType(bool v) async {
    _showCardType = v;
    await _storage.setSetting('showCardType', v.toString());
    notifyListeners();
  }

  Future<void> setShowCardExt(bool v) async {
    _showCardExt = v;
    await _storage.setSetting('showCardExt', v.toString());
    notifyListeners();
  }

  Future<void> setBgImagePath(String? path) async {
    _bgImagePath = path;
    await _storage.setSetting('bgImagePath', path ?? '');
    notifyListeners();
  }

  Future<void> setBgBlur(double v) async {
    if (v < 0 || v > 50) return;
    _bgBlur = v;
    await _storage.setSetting('bgBlur', v.toString());
    notifyListeners();
  }

  Future<void> setBgOpacity(double v) async {
    if (v < 0 || v > 1) return;
    _bgOpacity = v;
    await _storage.setSetting('bgOpacity', v.toString());
    notifyListeners();
  }

  Future<void> setMobileLongPress(String v) async {
    if (v != 'share' && v != 'menu') return;
    _mobileLongPress = v;
    await _storage.setSetting('mobileLongPress', v);
    notifyListeners();
  }

  Future<void> setTagSubdivision(bool v) async {
    _tagSubdivision = v;
    await _storage.setSetting('tagSubdivision', v ? 'true' : 'false');
    notifyListeners();
  }

  Future<void> toggleCategoryVisibility(String type) async {
    if (_hiddenCategories.contains(type)) {
      _hiddenCategories.remove(type);
    } else {
      _hiddenCategories.add(type);
    }
    await _storage.setSetting('hiddenCategories', _hiddenCategories.join(','));
    notifyListeners();
  }

  Future<void> addCustomCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _customCategories.contains(trimmed)) return;
    _customCategories = [..._customCategories, trimmed];
    await _storage.setSetting('customCategories', _customCategories.join(','));
    notifyListeners();
  }

  Future<void> removeCustomCategory(String name) async {
    _customCategories = _customCategories.where((c) => c != name).toList();
    await _storage.setSetting('customCategories', _customCategories.join(','));
    notifyListeners();
  }

  Future<void> setPreset(int index) async {
    _presetIndex = index;
    _useMonet = false;
    await _storage.setSetting('presetIndex', index.toString());
    await _storage.setSetting('useMonet', 'false');
    _syncImeTheme();
    notifyListeners();
  }

  /// 设置自定义种子色。M3 会从这个种子派生整套色板。
  Future<void> setCustomSeed(Color seed) async {
    _customSeed = seed;
    _presetIndex = AppTheme.presets.length;
    await _storage.setSetting('presetIndex', _presetIndex.toString());
    await _storage.setSetting('useMonet', 'false');
    await _storage.setSetting('customSeed', '#${seed.toARGB32().toRadixString(16).padLeft(8, '0')}');
    _syncImeTheme();
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
