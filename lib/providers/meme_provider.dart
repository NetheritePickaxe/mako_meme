import 'package:flutter/foundation.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:file_picker/file_picker.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import '../services/storage_service.dart';
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
  final Set<String> _sel = {};
  final Set<String> _tagFilter = {};
  String? _moodFilter;
  final Set<String> _folderFilter = {};

  Set<String> get folderFilter => _folderFilter;

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
  Set<String> get tagFilter => _tagFilter;
  String? get moodFilter => _moodFilter;

  List<String> get allTags {
    final s = <String>{};
    for (final m in _all) {
      s.addAll(m.tags);
    }
    return s.toList()..sort();
  }

  Future<void> init() => loadAll();

  Future<void> loadAll() async {
    _all = _storage.getAllMemes();
    _folders = _storage.getAllFolders();
    _apply();
    notifyListeners();
  }

  void selectFolder(String? id) {
    _folderId = id;
    _apply();
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    _apply();
    notifyListeners();
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

  void selectMood(String? moodId) {
    _moodFilter = moodId;
    _apply();
    notifyListeners();
  }

  void clearMood() {
    _moodFilter = null;
    _apply();
    notifyListeners();
  }

  Future<void> setMood(String memeId, String? moodId) async {
    await _storage.setMood(memeId, moodId);
    await loadAll();
  }

  Future<void> setMoodBatch(Set<String> ids, String? moodId) async {
    await _storage.setMoodBatch(ids.toList(), moodId);
    _sel.clear();
    _multi = false;
    await loadAll();
  }

  /// 按心情分组统计数量
  Map<String?, int> get moodCounts {
    final map = <String?, int>{};
    for (final m in _all) {
      map[m.mood] = (map[m.mood] ?? 0) + 1;
    }
    return map;
  }

  void toggleMulti() {
    _multi = !_multi;
    if (!_multi) _sel.clear();
    notifyListeners();
  }

  void toggleSelect(String id) {
    _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
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

  Future<List<Meme>> importFiles(List<PlatformFile> files, {String? folderId}) async {
    final memes = await _storage.importFiles(files, folderId: folderId ?? _folderId);
    await loadAll();
    return memes;
  }

  Future<Meme> importText(String text, {String? name, List<String> tags = const [], String? mood}) async {
    final meme = await _storage.importText(text, name: name, folderId: _folderId, tags: tags, mood: mood);
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
    if (_moodFilter != null) {
      list = list.where((m) => m.mood == _moodFilter).toList();
    }

    if (_tagFilter.isNotEmpty) {
      list = list.where((m) => _tagFilter.every((t) => m.tags.any((tag) => _matchWildcard(tag, t)))).toList();
    }
    if (_folderFilter.isNotEmpty) {
      list = list.where((m) => _folderFilter.any((fid) => m.folderId == fid)).toList();
    }
    if (_query.isNotEmpty) {
      if (_query.startsWith('#')) {
        final tq = _query.substring(1).toLowerCase();
        list = list.where((m) => m.tags.any((tag) => _matchWildcard(tag, tq))).toList();
      } else if (_query.startsWith('@')) {
        final fq = _query.substring(1).toLowerCase();
        final matchedFolderIds = _folders.where((f) => f.name.toLowerCase().contains(fq) || _matchWildcard(f.name, fq)).map((f) => f.id).toSet();
        list = list.where((m) => m.folderId != null && matchedFolderIds.contains(m.folderId)).toList();
      } else {
        final searchList = list.map((m) => '${m.name} ${m.tags.join(" ")}').toList();
        final fuse = Fuzzy(searchList, options: FuzzyOptions(threshold: 0.3));
        final results = fuse.search(_query);
        final matchedItems = results.where((r) => r.score < 0.7).map((r) => r.item).toSet();
        list = list.where((m) => matchedItems.contains('${m.name} ${m.tags.join(" ")}')).toList();
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
