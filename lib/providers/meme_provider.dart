import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import '../services/storage_service.dart';
import '../services/meme_index_exporter.dart';
import '../services/search_query.dart';
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

  String? _folderId;
  String _query = '';
  SortBy _sortBy = SortBy.date;
  SortOrder _order = SortOrder.desc;
  bool _multi = false;
  bool _showFoldersView = false;
  bool _showFavorites = false;
  final Set<String> _sel = {};
  final Set<String> _selectedFolders = {};
  final Set<String> _tagFilter = {};
  final Set<String> _folderFilter = {};
  final Set<String> _typeFilter = {};

  Set<String> get folderFilter => _folderFilter;
  Set<String> get typeFilter => _typeFilter;
  bool get showFoldersView => _showFoldersView;
  bool get showFavorites => _showFavorites;

  MemeProvider(this._storage, this._settings);

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

  List<String> get allTags {
    final s = <String>{};
    for (final m in _all) {
      s.addAll(m.tags);
    }
    return s.toList()..sort();
  }

  Future<void> init() => loadAll();

  MemeIndexExporter? _indexExporter;
  MemeIndexExporter get _exporter => _indexExporter ??= MemeIndexExporter(_storage);

  Future<void> loadAll() async {
    _all = _storage.getAllMemes();
    _folders = _storage.getAllFolders();
    _apply();
    notifyListeners();
    // 同步 meme 索引到原生 ContentProvider（供 IME 进程读取）
    _exporter.exportAll(_all);
  }

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

  /// 执行命令，返回结果消息（用于 snackbar 提示）
  /// 仅支持 CommandSearch 类型，其他返回 null
  Future<String?> executeCommand(String query) async {
    final result = SearchQuery.parse(query, _folders);
    if (result is! CommandSearch) return null;

    if (result.command == 'tag') {
      if (result.action.isEmpty) {
        return '缺少操作（add 或 remove）';
      }
      if (result.args.isEmpty) {
        return '缺少标签名';
      }
      final matcher = result.asMatcher(_folders);
      final targets = _all.where(matcher).toList();
      if (targets.isEmpty) return '没有匹配的表情包';

      final tags = result.args;
      if (result.action == 'add') {
        for (final meme in targets) {
          for (final tag in tags) {
            await _storage.addTagToMeme(meme.id, tag);
          }
        }
      } else if (result.action == 'remove') {
        for (final meme in targets) {
          for (final tag in tags) {
            await _storage.removeTagFromMeme(meme.id, tag);
          }
        }
      }
      await loadAll();
      final op = result.action == 'add' ? '添加' : '移除';
      return '已对 ${targets.length} 个表情包$op标签: ${tags.join(", ")}';
    }

    if (result.command == 'help') return null;
    return '未知命令: ${result.command}';
  }

  void toggleTag(String tag) {
    _tagFilter.contains(tag) ? _tagFilter.remove(tag) : _tagFilter.add(tag);
    _apply();
    notifyListeners();
  }

  void clearTagFilter() {
    _tagFilter.clear();
    _apply();
    notifyListeners();
  }

  void toggleFolderFilter(String folderId) {
    _folderFilter.contains(folderId) ? _folderFilter.remove(folderId) : _folderFilter.add(folderId);
    _apply();
    notifyListeners();
  }

  void clearFolderFilter() {
    _folderFilter.clear();
    _apply();
    notifyListeners();
  }

  void toggleTypeFilter(String type) {
    _typeFilter.contains(type) ? _typeFilter.remove(type) : _typeFilter.add(type);
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
      _folderId = null;
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
      _folderId = null;
      _showFoldersView = false;
    }
    _apply();
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

  void clearFolderSelection() {
    _selectedFolders.clear();
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
    await loadAll();
  }

  Future<void> deleteMeme(String id) async {
    await _storage.deleteMeme(id);
    _sel.remove(id);
    await loadAll();
  }

  Future<void> deleteSelected() async {
    await _storage.deleteMemes(_sel.toList());
    _sel.clear();
    _multi = false;
    await loadAll();
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    await _storage.moveToFolder(memeId, folderId);
    await loadAll();
  }

  Future<void> renameMeme(String id, String newName) async {
    await _storage.renameMeme(id, newName);
    await loadAll();
  }

  Future<void> updateMemeText(String id, String text, {String? name}) async {
    await _storage.updateMemeText(id, text, name: name);
    await loadAll();
  }

  Future<void> setMemeType(String id, String type) async {
    await _storage.setMemeType(id, type);
    await loadAll();
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
      final newType = (ratio <= ratioThreshold) ? Meme.typeEmoji : Meme.typeImage;
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
    await loadAll();
  }

  Future<void> moveSelectedToFolder(String? folderId) async {
    await _storage.moveToFolderBatch(_sel.toList(), folderId);
    _sel.clear();
    _multi = false;
    await loadAll();
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
    final memes = await _storage.importFiles(files, folderId: folderId ?? _folderId, autoClassify: autoClassify, classifyRatio: classifyRatio);
    await loadAll();
    return memes;
  }

  Future<Meme> importText(String text, {String? name, List<String> tags = const [], String type = Meme.typeText}) async {
    final meme = await _storage.importText(text, name: name, folderId: _folderId, tags: tags, type: type);
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

  String getFullMemePath(String rel) => _storage.getFullMemePath(rel);

  int countInFolder(String folderId) =>
      _all.where((m) => m.folderId == folderId).length;

  List<Meme> memesInFolder(String folderId) =>
      _all.where((m) => m.folderId == folderId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<Meme> get favorites => _all.where((m) => m.isFavorite).toList();

  bool _matchWildcard(String text, String pattern) {
    final lowerText = text.toLowerCase();
    final lowerPattern = pattern.toLowerCase();
    if (lowerPattern.contains('*')) {
      final regexPattern = '^${lowerPattern.replaceAll('*', '.*')}\$';
      return RegExp(regexPattern).hasMatch(lowerText);
    }
    return lowerText.contains(lowerPattern);
  }

  void _apply() {
    var list = List<Meme>.from(_all);
    if (_folderId != null) {
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
      list = list.where((m) => _typeFilter.contains(m.type)).toList();
    }
    if (_query.isNotEmpty) {
      final result = SearchQuery.parse(_query, _folders);
      // 命令不参与筛选（在 executeCommand 中执行），普通搜索和选择器正常筛选
      if (result is! CommandSearch) {
        final matcher = result.asMatcher(_folders);
        list = list.where(matcher).toList();
      }
    }

    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case SortBy.date: cmp = a.createdAt.compareTo(b.createdAt); break;
        case SortBy.name: cmp = a.name.compareTo(b.name); break;
        case SortBy.size: cmp = a.fileSize.compareTo(b.fileSize); break;
      }
      return _order == SortOrder.asc ? cmp : -cmp;
    });
    _filtered = list;
  }
}
