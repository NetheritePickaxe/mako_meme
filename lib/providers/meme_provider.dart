import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import '../services/storage_service.dart';
import '../services/meme_index_exporter.dart';
import '../services/search_query.dart';
import '../services/system_gallery_service.dart';
import '../services/webdav_service.dart';
import 'settings_provider.dart';

enum SortBy { date, name, size }
enum SortOrder { asc, desc }

class MemeProvider with ChangeNotifier {
  final StorageService _storage;
  final SettingsProvider _settings;
  List<Meme> _all = [];
  List<Meme> _filtered = [];
  List<MemeFolder> _folders = [];
  // 系统图集虚拟 Meme 列表（从绑定的系统目录扫描得到，不存数据库）
  List<Meme> _systemGalleryMemes = [];

  String? _folderId;
  String _query = '';
  SortBy _sortBy = SortBy.date;
  SortOrder _order = SortOrder.desc;
  bool _multi = false;
  bool _showFoldersView = false;
  bool _showFavorites = false;
  Meme? _previewMeme;
  final Set<String> _sel = {};
  final Set<String> _selectedFolders = {};
  final Set<String> _tagFilter = {};
  final Set<String> _folderFilter = {};
  final Set<String> _typeFilter = {};
  // 情绪筛选：null=全部，否则只显示该 mood 的 memes
  String? _moodFilter;

  // 缓存
  Map<String, List<Meme>>? _memesByMoodCache;
  final Map<String, RegExp> _wildcardCache = {};

  Set<String> get folderFilter => _folderFilter;
  Set<String> get typeFilter => _typeFilter;
  String? get moodFilter => _moodFilter;
  bool get showFoldersView => _showFoldersView;
  bool get showFavorites => _showFavorites;
  Meme? get previewMeme => _previewMeme;

  MemeProvider(this._storage, this._settings) {
    // 监听设置变化（如 excludeFoldered 切换）后重新筛选
    _settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // 系统图集配置变更时异步重新加载虚拟 Meme
    if (_settings.systemGalleryEnabled && _settings.systemGalleryPaths.isNotEmpty) {
      _loadSystemGalleryMemes().then((_) {
        _apply();
        notifyListeners();
      });
    } else {
      _systemGalleryMemes = [];
      _typeFilter.remove(Meme.typeSystemGallery);
      _apply();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  List<Meme> get memes => _filtered;
  int get allMemesCount => _all.length;
  List<MemeFolder> get folders => _folders;
  String? get folderId => _folderId;
  String get query => _query;
  SortBy get sortBy => _sortBy;
  SortOrder get order => _order;
  bool get isMulti => _multi;
  Set<String> get selected => _sel;
  Set<String> get selectedFolders => _selectedFolders;
  Set<String> get tagFilter => _tagFilter;

  /// 当前选中的 Meme 列表（基于 _all 匹配 selected id）
  List<Meme> get selectedMemes =>
      _all.where((m) => _sel.contains(m.id)).toList();

  List<String> get allTags {
    final s = <String>{};
    for (final m in _all) {
      s.addAll(m.tags);
    }
    // 过滤掉 __ 开头的系统内部 tag（如系统图集标记），不污染用户标签列表
    s.removeWhere((t) => t.startsWith('__'));
    return s.toList()..sort();
  }

  /// 所有情绪标签（去重排序）
  List<String> get allMoods {
    final s = <String>{};
    for (final m in _all) {
      for (final mood in m.moods) {
        s.add(mood['name'] as String);
      }
    }
    return s.toList()..sort();
  }

  /// 按情绪分组：moodName 映射到对应的 Meme 列表（按权重降序）
  Map<String, List<Meme>> get memesByMood {
    if (_memesByMoodCache != null) return _memesByMoodCache!;
    final map = <String, List<Meme>>{};
    for (final m in _all) {
      for (final mood in m.moods) {
        final name = mood['name'] as String;
        map.putIfAbsent(name, () => []).add(m);
      }
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final aw = a.moods.firstWhere((m) => m['name'] == entry.key,
            orElse: () => {'weight': 0})['weight'] as int;
        final bw = b.moods.firstWhere((m) => m['name'] == entry.key,
            orElse: () => {'weight': 0})['weight'] as int;
        return bw.compareTo(aw);
      });
    }
    _memesByMoodCache = map;
    return map;
  }

  Future<void> init() => loadAll();

  MemeIndexExporter? _indexExporter;
  MemeIndexExporter get _exporter => _indexExporter ??= MemeIndexExporter(_storage);

  Future<void> loadAll() async {
    _all = _storage.getAllMemes();
    _folders = _storage.getAllFolders();
    _memesByMoodCache = null;
    await _loadSystemGalleryMemes();
    _apply();
    notifyListeners();
    _exporter.exportAll(_all);
  }

  /// 扫描所有绑定的系统图集目录，构建虚拟 Meme 列表
  Future<void> _loadSystemGalleryMemes() async {
    if (!_settings.systemGalleryEnabled || _settings.systemGalleryPaths.isEmpty) {
      _systemGalleryMemes = [];
      return;
    }
    final all = <Meme>[];
    for (final dirPath in _settings.systemGalleryPaths) {
      final images = await SystemGalleryService.listImages(dirPath);
      for (final img in images) {
        try {
          all.add(await SystemGalleryService.buildVirtualMeme(img));
        } catch (_) {}
      }
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _systemGalleryMemes = all;
  }

  /// 手动刷新系统图集（设置页绑定/解绑目录后调用）
  Future<void> refreshSystemGallery() async {
    await _loadSystemGalleryMemes();
    _apply();
    notifyListeners();
  }

  /// 系统图集虚拟 Meme 列表（用于详情面板计数等）
  List<Meme> get systemGalleryMemes => List.unmodifiable(_systemGalleryMemes);

  void selectFolder(String? id) {
    _folderId = id;
    if (id != null) _showFoldersView = false;
    _apply();
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    _apply();
    notifyListeners();
  }

  /// 当前查询是否为命令（用于搜索栏判断是否在输入命令）
  bool get isCommandQuery =>
      _query.trim().startsWith('/') &&
      SearchQuery.parse(_query, _folders) is CommandSearch;

  /// 执行命令，返回结果消息（key + args，用于 snackbar 翻译）
  ({String key, Map<String, String> args})? executeCommand(String query) {
    final result = SearchQuery.parse(query, _folders);
    if (result is! CommandSearch) return null;

    if (result.command == 'tag') {
      if (result.action.isEmpty) {
        return (key: 'cmd_missing_action', args: {});
      }
      if (result.args.isEmpty) {
        return (key: 'cmd_missing_tag', args: {});
      }
      final matcher = result.asMatcher(_folders);
      final targets = _all.where(matcher).toList();
      if (targets.isEmpty) return (key: 'cmd_no_match', args: {});

      final tags = result.args;
      if (result.action == 'add') {
        for (final meme in targets) {
          for (final tag in tags) {
            _storage.addTagToMeme(meme.id, tag);
          }
        }
      } else if (result.action == 'remove') {
        for (final meme in targets) {
          for (final tag in tags) {
            _storage.removeTagFromMeme(meme.id, tag);
          }
        }
      }
      loadAll();
      final op = result.action == 'add' ? 'cmd_tag_added' : 'cmd_tag_removed';
      return (
        key: op,
        args: {'count': targets.length.toString(), 'tags': tags.join(', ')},
      );
    }

    if (result.command == 'help') return null;
    return (key: 'cmd_unknown', args: {'cmd': result.command});
  }

  void toggleTag(String tag) {
    _tagFilter.contains(tag) ? _tagFilter.remove(tag) : _tagFilter.add(tag);
    _apply();
    notifyListeners();
  }

  /// 设置情绪筛选（null=清除筛选）
  void setMoodFilter(String? mood) {
    _moodFilter = mood;
    _apply();
    notifyListeners();
  }

  /// 给单个 meme 添加 tag
  Future<void> addTag(String memeId, String tag) async {
    await _storage.addTagToMeme(memeId, tag);
    _refreshMeme(memeId);
  }

  /// 给单个 meme 移除 tag
  Future<void> removeTag(String memeId, String tag) async {
    await _storage.removeTagFromMeme(memeId, tag);
    _refreshMeme(memeId);
  }

  /// 给单个 meme 添加/更新情绪标签（权重 1-5）
  Future<void> addMood(String memeId, String mood, int weight) async {
    await _storage.addMoodToMeme(memeId, mood, weight);
    _refreshMeme(memeId);
  }

  /// 给单个 meme 移除情绪标签
  Future<void> removeMood(String memeId, String mood) async {
    await _storage.removeMoodFromMeme(memeId, mood);
    _refreshMeme(memeId);
  }

  void toggleFolderFilter(String folderId) {
    _folderFilter.contains(folderId) ? _folderFilter.remove(folderId) : _folderFilter.add(folderId);
    _apply();
    notifyListeners();
  }

  void toggleTypeFilter(String type) {
    // 系统图集是特殊分类，与其他类型互斥：选中 system_gallery 时清空其他，
    // 选中其他类型时移除 system_gallery
    if (type == Meme.typeSystemGallery) {
      if (_typeFilter.contains(type)) {
        _typeFilter.remove(type);
      } else {
        _typeFilter.clear();
        _typeFilter.add(type);
      }
    } else {
      _typeFilter.remove(Meme.typeSystemGallery);
      if (_typeFilter.contains(type)) {
        _typeFilter.remove(type);
      } else {
        _typeFilter.add(type);
      }
    }
    _apply();
    notifyListeners();
  }

  void clearTypeFilter() {
    _typeFilter.clear();
    _apply();
    notifyListeners();
  }

  void setTypeFilter(String? type) {
    _typeFilter.clear();
    if (type != null) {
      _typeFilter.add(type);
    }
    _apply();
    notifyListeners();
  }

  void setSort(SortBy b) {
    _sortBy = b;
    _apply();
    notifyListeners();
  }

  void toggleOrder() {
    _order = _order == SortOrder.asc ? SortOrder.desc : SortOrder.asc;
    _apply();
    notifyListeners();
  }

  void toggleMulti() {
    _multi = !_multi;
    if (!_multi) {
      _sel.clear();
      _selectedFolders.clear();
    }
    notifyListeners();
  }

  void setShowFoldersView(bool v) {
    _showFoldersView = v;
    if (v) {
      // 进入文件夹视图时不清除 _folderId，以便切回表情包 tab 时保持原文件夹
      _typeFilter.clear();
      _tagFilter.clear();
      _folderFilter.clear();
      _apply();
    }
    notifyListeners();
  }

  void setShowFavorites(bool v) {
    _showFavorites = v;
    if (v) {
      // 进入收藏视图时不清除 _folderId，以便切回表情包 tab 时保持原文件夹
      _showFoldersView = false;
    }
    _apply();
    notifyListeners();
  }

  /// 设置当前预览的 meme（横屏预览模式）
  void setPreviewMeme(Meme? meme) {
    _previewMeme = meme;
    notifyListeners();
  }

  /// 清除预览选中（如切换标签、过滤变化时）
  void clearPreviewMeme() {
    if (_previewMeme == null) return;
    _previewMeme = null;
    notifyListeners();
  }

  void toggleSelect(String id) {
    _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
    notifyListeners();
  }

  void toggleFolderSelect(String id) {
    _selectedFolders.contains(id) ? _selectedFolders.remove(id) : _selectedFolders.add(id);
    notifyListeners();
  }

  void selectAll() {
    _sel.addAll(_filtered.map((m) => m.id));
    notifyListeners();
  }

  void deselectAll() {
    _sel.clear();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    await _storage.toggleFavorite(id);
    _refreshMeme(id);
  }

  Future<void> deleteMeme(String id) async {
    await _storage.deleteMeme(id);
    _sel.remove(id);
    _all.removeWhere((m) => m.id == id);
    _memesByMoodCache = null;
    _apply();
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    await _storage.deleteMemes(_sel.toList());
    _all.removeWhere((m) => _sel.contains(m.id));
    _sel.clear();
    _multi = false;
    _memesByMoodCache = null;
    _apply();
    notifyListeners();
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    await _storage.moveToFolder(memeId, folderId);
    _refreshMeme(memeId);
  }

  Future<void> renameMeme(String id, String newName) async {
    await _storage.renameMeme(id, newName);
    _refreshMeme(id);
  }

  Future<void> updateMemeText(String id, String text, {String? name}) async {
    await _storage.updateMemeText(id, text, name: name);
    _refreshMeme(id);
  }

  Future<void> setMemeType(String id, String type) async {
    await _storage.setMemeType(id, type);
    _refreshMeme(id);
  }

  Future<void> setSelectedType(String type) async {
    for (final id in _sel) {
      await _storage.setMemeType(id, type);
    }
    await loadAll();
  }

  /// 按画幅重新归类所有图片类表情包（不动角色卡/GIF/文字）
  /// 返回归类后的统计
  Future<Map<String, int>> reclassifyAllByAspectRatio(double ratioThreshold) async {
    int emojiCount = 0;
    int imageCount = 0;
    int skipped = 0;
    for (final meme in List<Meme>.from(_all)) {
      // 只处理图片类和当前归类为表情/图片的
      if (meme.type != Meme.typeImage && meme.type != Meme.typeEmoji) {
        skipped++;
        continue;
      }
      if (meme.filePath.isEmpty) {
        skipped++;
        continue;
      }
      final ratio = await _storage.getImageAspectRatio(meme.filePath);
      if (ratio == null || ratio <= 0) {
        skipped++;
        continue;
      }
      // 归一化：宽高比取 max(ratio, 1/ratio)，让竖图（ratio<1）也能正确归类为图片
      // 否则竖图（如 9:16，ratio=0.56）会被错误归入表情
      final normalized = ratio >= 1 ? ratio : 1 / ratio;
      final newType = (normalized <= ratioThreshold) ? Meme.typeEmoji : Meme.typeImage;
      if (newType != meme.type) {
        await _storage.setMemeType(meme.id, newType);
        if (newType == Meme.typeEmoji) {
          emojiCount++;
        } else {
          imageCount++;
        }
      }
    }
    await loadAll();
    return {'emoji': emojiCount, 'image': imageCount, 'skipped': skipped};
  }

  Future<void> updateFolderCover(String folderId, String? coverMemeId) async {
    await _storage.updateFolderCover(folderId, coverMemeId);
    await loadAll();
  }

  Future<void> updateCharacterData(String id, Map<String, dynamic> data) async {
    await _storage.updateCharacterData(id, data);
    _refreshMeme(id);
  }

  Future<void> moveSelectedToFolder(String? folderId) async {
    await _storage.moveToFolderBatch(_sel.toList(), folderId);
    final ids = _sel.toList();
    _sel.clear();
    _multi = false;
    _memesByMoodCache = null;
    for (final id in ids) {
      final meme = _storage.getMeme(id);
      if (meme != null) {
        final idx = _all.indexWhere((m) => m.id == id);
        if (idx >= 0) _all[idx] = meme;
      }
    }
    _apply();
    notifyListeners();
  }

  Future<MemeFolder> createFolder(String name) async {
    final f = await _storage.createFolder(name);
    await loadAll();
    return f;
  }

  Future<void> renameFolder(String id, String newName) async {
    final f = _folders.firstWhere((f) => f.id == id);
    await _storage.updateFolder(f.copyWith(name: newName));
    await loadAll();
  }

  Future<void> deleteFolder(String id) async {
    await _storage.deleteFolder(id);
    if (_folderId == id) _folderId = null;
    await loadAll();
  }

  Future<List<Meme>> importFiles(List<PlatformFile> files, {String? folderId, bool autoClassify = false, double classifyRatio = 1.1}) async {
    if (files.isEmpty) return [];
    final targetFolderId = folderId ?? _folderId;
    debugPrint('[Mako] importFiles START: ${files.length} files, targetFolderId=$targetFolderId, '
        'current folderId=$_folderId, typeFilter=$_typeFilter, _all.length=${_all.length}');

    // 逐张写入存储（不在循环中刷新 UI，避免占位卡片与真实数据交叉导致主界面闪烁/消失）
    final results = <Meme>[];
    for (var i = 0; i < files.length; i++) {
      try {
        final m = await _storage.importFile(
          files[i],
          folderId: targetFolderId,
          autoClassify: autoClassify,
          classifyRatio: classifyRatio,
        );
        results.add(m);
        debugPrint('[Mako] importFiles[$i] ok: id=${m.id}, name="${m.name}", '
            'type=${m.type}, filePath="${m.filePath}", folderId=${m.folderId}');
      } catch (e, st) {
        debugPrint('[Mako] importFiles[$i] ERROR: $e, st=$st');
      }
    }
    // 全部导入完成后统一刷新一次，确保 _all/_filtered 与存储一致
    await loadAll();
    debugPrint('[Mako] importFiles DONE: results=${results.length}, '
        '_all.length=${_all.length}, _filtered.length=${_filtered.length}');
    return results;
  }

  Future<Meme> importText(String text, {String? name, List<String> tags = const [], String type = Meme.typeText}) async {
    final meme = await _storage.importText(text, name: name, folderId: _folderId, tags: tags, type: type);
    await loadAll();
    return meme;
  }

  /// 从文本文件导入（支持 txt / md / doc / docx 等格式）
  /// 自动判断类型：大文件/doc/docx/md 视为小说，小 txt 视为文字
  Future<Meme> importTextFile(PlatformFile file, {String? type}) async {
    final meme = await _storage.importTextFile(file, folderId: _folderId, type: type);
    await loadAll();
    return meme;
  }

  /// 导入漫画（手动多图合并）
  Future<Meme> importMangaFromFiles(List<PlatformFile> files, {String? name}) async {
    final meme = await _storage.importMangaFromFiles(files, name: name, folderId: _folderId);
    await loadAll();
    return meme;
  }

  /// 导入漫画（从 CBZ/ZIP 压缩包）
  Future<Meme> importMangaFromArchive(PlatformFile file, {String? name}) async {
    final meme = await _storage.importMangaFromArchive(file, name: name, folderId: _folderId);
    await loadAll();
    return meme;
  }

  /// 导入立绘/CG（多图合并为精灵图层）
  Future<Meme> importSpriteFromFiles(
    List<PlatformFile> files, {
    String? name,
    required String type,
    List<String>? categories,
  }) async {
    final meme = await _storage.importSpriteFromFiles(
      files,
      name: name,
      folderId: _folderId,
      type: type,
      categories: categories,
    );
    await loadAll();
    return meme;
  }

  /// 导入立绘/CG（从 krkr pjson + 图片文件）
  Future<Meme> importSpriteFromPjson(
    PlatformFile pjsonFile,
    List<PlatformFile> imageFiles, {
    String? name,
    required String type,
  }) async {
    final meme = await _storage.importSpriteFromPjson(
      pjsonFile,
      imageFiles,
      name: name,
      folderId: _folderId,
      type: type,
    );
    await loadAll();
    return meme;
  }

  /// 导入序列帧图片
  Future<Meme> importSpriteSheet(
    PlatformFile file, {
    required int cols,
    required int rows,
    String? name,
  }) async {
    final meme = await _storage.importSpriteSheet(
      file,
      cols: cols,
      rows: rows,
      name: name,
      folderId: _folderId,
    );
    await loadAll();
    return meme;
  }

  /// 同步所有 meme 到 WebDAV
  Future<void> syncAllToWebDav() async {
    if (!_settings.useWebDav || _settings.webDavBaseUrl == null) return;
    
    final webDavService = WebDavService(
      baseUrl: _settings.webDavBaseUrl!,
      username: _settings.webDavUsername!,
      password: _settings.webDavPassword!,
    );
    
    for (final meme in _all) {
      if (meme.remotePath == null && meme.filePath.isNotEmpty) {
        final bytes = await _storage.readMemeBytes(meme.filePath);
        if (bytes != null) {
          await _storage.syncToWebDav(meme, bytes, webDavService);
        }
      }
    }
  }

  int countInFolder(String folderId) =>
      _all.where((m) => m.folderId == folderId).length;

  List<Meme> memesInFolder(String folderId) =>
      _all.where((m) => m.folderId == folderId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Meme> get favorites => _all.where((m) => m.isFavorite).toList();

  void _refreshMeme(String id) {
    final meme = _storage.getMeme(id);
    if (meme == null) return;
    final idx = _all.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      _all[idx] = meme;
    } else {
      _all.add(meme);
    }
    _memesByMoodCache = null;
    _apply();
    notifyListeners();
  }

  Future<void> forceRefresh() async {
    await loadAll();
  }

  Future<void> clearCache() async {
    await _storage.clearThumbnailCache();
    await loadAll();
  }

  void _sortMemeList(List<Meme> list) {
    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case SortBy.date: cmp = a.createdAt.compareTo(b.createdAt); break;
        case SortBy.name: cmp = a.name.compareTo(b.name); break;
        case SortBy.size: cmp = a.fileSize.compareTo(b.fileSize); break;
      }
      return _order == SortOrder.asc ? cmp : -cmp;
    });
  }

  bool _matchWildcard(String text, String pattern) {
    final lowerText = text.toLowerCase();
    final lowerPattern = pattern.toLowerCase();
    if (lowerPattern.contains('*')) {
      final regexPattern = '^${lowerPattern.replaceAll('*', '.*')}\$';
      final regex = _wildcardCache.putIfAbsent(regexPattern, () => RegExp(regexPattern));
      return regex.hasMatch(lowerText);
    }
    return lowerText.contains(lowerPattern);
  }

  void _apply() {
    // 系统图集分类：特殊处理，只显示虚拟 Meme（不参与常规筛选）
    if (_typeFilter.contains(Meme.typeSystemGallery)) {
      var list = List<Meme>.from(_systemGalleryMemes);
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        list = list.where((m) => m.name.toLowerCase().contains(q)).toList();
      }
      _sortMemeList(list);
      _filtered = list;
      return;
    }

    var list = List<Meme>.from(_all);
    // 文件夹筛选仅在表情包 tab（非收藏视图）生效；
    // 切到收藏/文件夹 tab 时保留 _folderId 但不应用，以便切回时恢复
    if (_folderId != null && !_showFavorites && !_showFoldersView) {
      list = list.where((m) => m.folderId == _folderId).toList();
    }
    if (_showFavorites) {
      list = list.where((m) => m.isFavorite).toList();
    }
    if (_tagFilter.isNotEmpty) {
      list = list.where((m) => _tagFilter.every((t) => m.tags.any((tag) => _matchWildcard(tag, t)))).toList();
    }
    if (_folderFilter.isNotEmpty) {
      list = list.where((m) => _folderFilter.any((fid) => m.folderId == fid)).toList();
    }
    if (_typeFilter.isNotEmpty) {
      // md/novel 归入文字分类：选 typeText 时也匹配 typeMd、typeNovel
      // PDF 归入文件分类：选 typeFile 时也匹配 typePdf
      list = list.where((m) {
        if (_typeFilter.contains(m.type)) return true;
        if ((m.type == Meme.typeMd || m.type == Meme.typeNovel) &&
            _typeFilter.contains(Meme.typeText)) return true;
        if (m.type == Meme.typePdf && _typeFilter.contains(Meme.typeFile)) return true;
        return false;
      }).toList();
    }
    if (_moodFilter != null) {
      list = list.where((m) => m.moods.any((mo) => mo['name'] == _moodFilter)).toList();
    }
    // 主界面（全部 / 表情包 tab，未进入文件夹、未在收藏/文件夹视图）排除已归入文件夹的图片
    if (_settings.excludeFoldered &&
        _folderId == null &&
        !_showFavorites &&
        !_showFoldersView &&
        _moodFilter == null) {
      list = list.where((m) => m.folderId == null).toList();
    }
    if (_query.isNotEmpty) {
      final result = SearchQuery.parse(_query, _folders);
      // 命令不参与筛选（在 executeCommand 中执行），普通搜索和选择器正常筛选
      if (result is! CommandSearch) {
        final matcher = result.asMatcher(_folders);
        list = list.where(matcher).toList();
      }
    }

    _sortMemeList(list);
    _filtered = list;
    // 诊断日志：当筛选结果为空但全量数据非空时，记录筛选状态以便定位问题
    if (_filtered.isEmpty && _all.isNotEmpty) {
      debugPrint('[Mako] _apply EMPTY: _all.length=${_all.length}, '
          'folderId=$_folderId, showFavorites=$_showFavorites, '
          'showFoldersView=$_showFoldersView, typeFilter=$_typeFilter, '
          'tagFilter=$_tagFilter, folderFilter=$_folderFilter, '
          'moodFilter=$_moodFilter, excludeFoldered=${_settings.excludeFoldered}, '
          'query="$_query"');
    }
  }
}
