import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:archive/archive_io.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import 'storage_platform.dart';
import 'webdav_service.dart';
import 'admin_service.dart';

/// JSON 文件存储 — 跨平台，Web 上使用 IndexedDB
class StorageService {
  final Uuid _uuid = const Uuid();
  List<Meme> _memes = [];
  List<MemeFolder> _folders = [];
  String? _basePath;
  String? _userId;
  String _storageMode = 'personal';

  static const int _chunkSize = 1000;
  static const String _metaFile = 'meta.json';
  static const String _memesPrefix = 'memes_';
  static const String _oldMemesFile = 'memes.json';
  static const int _storageVersion = 2;

  String get basePath => _basePath ?? '.';
  String? get userId => _userId;
  String get storageMode => _storageMode;

  Future<void> init({String? userId}) async {
    _userId = userId ?? _getDefaultUserId();

    final config = ConfigLoader.config;
    final storageConfig = config?['storage'] as Map<String, dynamic>?;
    _storageMode = storageConfig?['mode'] as String? ?? 'personal';

    if (kIsWeb) {
      await _initWeb();
      await _loadFromWeb();
      await _loadSettingsFromWeb();
    } else {
      // 先加载设置以获取存储位置
      await _loadSettingsEarly();
      final customPath = _settings['customStoragePath'];
      final storageLocation = _settings['storageLocation'] ?? 'app';

      if (storageLocation == 'custom' && customPath != null && customPath.isNotEmpty) {
        _basePath = p.join(customPath, 'mako_meme');
      } else {
        final dir = await getApplicationDocumentsDirectory();
        _basePath = _getPlatformBasePath(dir.path);
      }
      final storageDir = Directory(_basePath!);
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }
      _loadFromFile();
    }
  }

  Future<void> _loadSettingsEarly() async {
    if (_settingsLoaded) return;
    // 尝试从应用默认路径读取设置
    try {
      final dir = await getApplicationDocumentsDirectory();
      final defaultPath = _getPlatformBasePath(dir.path);
      final file = File(p.join(defaultPath, 'settings.json'));
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _settings = data.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    _settingsLoaded = true;
  }

  String _getDefaultUserId() {
    if (!kIsWeb) return 'default';
    try {
      final uri = Uri.base;
      final userIdParam = uri.queryParameters['user'];
      if (userIdParam != null && userIdParam.isNotEmpty) {
        return userIdParam;
      }
    } catch (_) {}
    return 'default';
  }

  String _getPlatformBasePath(String appDir) {
    if (_storageMode == 'shared') {
      return p.join(appDir, 'mako_meme', 'shared');
    }
    return p.join(appDir, 'mako_meme', 'users', _userId ?? 'default');
  }

  // ======================== Web 存储 (IndexedDB) ========================

  Future<void> _initWeb() async {
    try {
      await initWebStorage();
    } catch (_) {}
  }

  Future<void> _loadFromWeb() async {
    try {
      final key = _storageMode == 'shared' ? 'mako_memes_shared' : 'mako_memes_${_userId ?? 'default'}';
      final raw = await webStorageGetJson(key);
      if (raw != null && raw is String) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _memes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        _folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _saveToWeb() async {
    try {
      final key = _storageMode == 'shared' ? 'mako_memes_shared' : 'mako_memes_${_userId ?? 'default'}';
      final data = jsonEncode({
        'memes': _memes.map((m) => m.toMap()).toList(),
        'folders': _folders.map((f) => f.toMap()).toList(),
      });
      await webStorageSetJson(key, data);
    } catch (_) {}
  }

  // ======================== 文件存储 (Native) ========================

  void _loadFromFile() {
    _migrateIfNeeded();
    _loadMeta();
    _loadAllChunks();
  }

  void _migrateIfNeeded() {
    final oldFile = File(p.join(_basePath!, _oldMemesFile));
    if (!oldFile.existsSync()) return;

    try {
      final data = jsonDecode(oldFile.readAsStringSync()) as Map<String, dynamic>;
      final memes = (data['memes'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map((m) => Meme.fromMap(m))
          .toList();
      final folders = (data['folders'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map((f) => MemeFolder.fromMap(f))
          .toList();

      _memes = memes;
      _folders = folders;
      _saveMeta();
      _saveAllChunks();

      oldFile.renameSync(p.join(_basePath!, '${_oldMemesFile}.bak'));
    } catch (_) {}
  }

  void _loadMeta() {
    final metaFile = File(p.join(_basePath!, _metaFile));
    if (!metaFile.existsSync()) {
      _folders = [];
      return;
    }
    try {
      final data = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      final version = data['version'] as int? ?? 1;
      if (version < _storageVersion) {
        _migrateFromMetaV1(data);
      } else {
        _folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      }
    } catch (_) {
      _folders = [];
    }
  }

  void _migrateFromMetaV1(Map<String, dynamic> data) {
    _folders = (data['folders'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map((f) => MemeFolder.fromMap(f))
        .toList();
    _memes = (data['memes'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map((m) => Meme.fromMap(m))
        .toList();
    _saveMeta();
    _saveAllChunks();
  }

  void _loadAllChunks() {
    _memes = [];
    final dir = Directory(_basePath!);
    if (!dir.existsSync()) return;

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith(_memesPrefix) && p.extension(f.path) == '.json')
        .map((f) {
          final name = p.basenameWithoutExtension(f.path);
          final numStr = name.substring(_memesPrefix.length);
          final index = int.tryParse(numStr);
          return {'file': f, 'index': index};
        })
        .where((e) => e['index'] != null)
        .toList()
      ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

    for (final item in files) {
      final file = item['file'] as File;
      try {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final chunkMemes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        _memes.addAll(chunkMemes);
      } catch (_) {}
    }
  }

  void _saveToFile() {
    try {
      _saveMeta();
      _saveAllChunks();
    } catch (_) {}
  }

  void _saveMeta() {
    final metaFile = File(p.join(_basePath!, _metaFile));
    metaFile.writeAsStringSync(jsonEncode({
      'version': _storageVersion,
      'folders': _folders.map((f) => f.toMap()).toList(),
    }));
  }

  void _saveAllChunks() {
    final dir = Directory(_basePath!);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final existingChunks = dir.listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith(_memesPrefix) && p.extension(f.path) == '.json')
        .toList();

    final chunkCount = (_memes.length / _chunkSize).ceil();
    for (var i = 0; i < chunkCount; i++) {
      final start = i * _chunkSize;
      final end = min(start + _chunkSize, _memes.length);
      final chunk = _memes.sublist(start, end);
      final chunkFile = File(p.join(_basePath!, '${_memesPrefix}${i.toString().padLeft(3, '0')}.json'));
      chunkFile.writeAsStringSync(jsonEncode({
        'memes': chunk.map((m) => m.toMap()).toList(),
      }));
    }

    for (final file in existingChunks) {
      final name = p.basename(file.path);
      final numStr = name.substring(_memesPrefix.length).replaceAll('.json', '');
      final index = int.tryParse(numStr);
      if (index != null && index >= chunkCount) {
        file.deleteSync();
      }
    }
  }

  void _save() {
    if (kIsWeb) {
      _saveToWeb();
    } else {
      _saveToFile();
    }
  }

  // ======================== Meme CRUD ========================

  List<Meme> getAllMemes() => List.unmodifiable(_memes);
  List<MemeFolder> getAllFolders() => List.unmodifiable(_folders);

  String getFullMemePath(String relPath) {
    if (kIsWeb) return relPath;
    final base = _basePath;
    if (base == null) return relPath;
    return p.join(base, relPath);
  }

  Future<Meme> importFile(PlatformFile file, {String? folderId, String? type}) async {
    final id = _uuid.v4();
    final ext = _guessExt(file.name);
    final fileName = '$id$ext';
    final now = DateTime.now();

    Uint8List? bytes;
    String filePath;

    if (kIsWeb) {
      // Web: 存储图片字节到 IndexedDB
      bytes = file.bytes;
      filePath = 'memes/$fileName';
      if (bytes != null) {
        await webStorageSetBinary(filePath, bytes);
      }
    } else {
      // Native: 复制文件到存储目录
      filePath = 'memes/$fileName';
      final dest = File(p.join(_basePath!, filePath));
      await dest.create(recursive: true);
      if (file.path != null) {
        await File(file.path!).copy(dest.path);
      } else if (file.bytes != null) {
        await dest.writeAsBytes(file.bytes!);
      }
    }

    final memeType = type ?? _guessType(ext);

    final meme = Meme(
      id: id,
      name: p.basenameWithoutExtension(file.name),
      filePath: filePath,
      folderId: folderId,
      tags: [],
      createdAt: now,
      mimeType: _guessMime(ext),
      fileSize: bytes?.length ?? file.size,
      type: memeType,
    );
    _memes.insert(0, meme);
    _save();
    return meme;
  }

  /// 获取图片字节（跨平台）
  Future<Uint8List?> readMemeBytes(String filePath) async {
    if (kIsWeb) {
      return await webStorageGetBinary(filePath);
    }
    try {
      final file = File(p.join(_basePath!, filePath));
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  Future<List<Meme>> importFiles(List<PlatformFile> files, {String? folderId}) async {
    final results = <Meme>[];
    for (final file in files) {
      results.add(await importFile(file, folderId: folderId));
    }
    return results;
  }

  /// 重新导入图片（保留原元数据，只替换文件字节）
  Future<void> reimportMeme(String memeId, PlatformFile file) async {
    final idx = _memes.indexWhere((m) => m.id == memeId);
    if (idx == -1) return;
    final old = _memes[idx];

    if (kIsWeb) {
      if (file.bytes != null) {
        await webStorageSetBinary(old.filePath, file.bytes!);
      }
    } else {
      final dest = File(p.join(_basePath!, old.filePath));
      await dest.create(recursive: true);
      if (file.path != null) {
        await File(file.path!).copy(dest.path);
      } else if (file.bytes != null) {
        await dest.writeAsBytes(file.bytes!);
      }
    }
    // 更新文件大小和类型
    _memes[idx] = old.copyWith(
      mimeType: _guessMime(_guessExt(file.name)),
      fileSize: file.size,
    );
    _save();
  }

  Future<Meme> importText(String text, {String? name, String? folderId, List<String> tags = const []}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final meme = Meme(
      id: id,
      name: name ?? text.substring(0, text.length.clamp(0, 30)),
      filePath: '',
      folderId: folderId,
      tags: tags,
      createdAt: now,
      mimeType: '',
      fileSize: text.length,
      type: 'text',
      textContent: text,
    );
    _memes.insert(0, meme);
    _save();
    return meme;
  }

  Future<void> deleteMeme(String id) async {
    final meme = _memes.where((m) => m.id == id).firstOrNull;
    if (meme != null && !kIsWeb && meme.filePath.isNotEmpty) {
      final file = File(p.join(_basePath!, meme.filePath));
      if (await file.exists()) await file.delete();
    }
    // Web: 删除 IndexedDB 中的图片
    if (kIsWeb && meme != null && meme.filePath.isNotEmpty) {
      await webStorageDelete(meme.filePath);
    }
    _memes.removeWhere((m) => m.id == id);
    _save();
  }

  Future<void> deleteMemes(List<String> ids) async {
    for (final id in ids) {
      await deleteMeme(id);
    }
  }

  Future<void> renameMeme(String id, String newName) async {
    final idx = _memes.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _memes[idx] = _memes[idx].copyWith(name: newName);
      _save();
    }
  }

  Future<void> setMemeType(String id, String type) async {
    final idx = _memes.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _memes[idx] = _memes[idx].copyWith(type: type);
      _save();
    }
  }

  Future<void> toggleFavorite(String id) async {
    final meme = _memes.where((m) => m.id == id).firstOrNull;
    if (meme != null) {
      meme.isFavorite = !meme.isFavorite;
      _save();
    }
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    final idx = _memes.indexWhere((m) => m.id == memeId);
    if (idx != -1) {
      _memes[idx] = _memes[idx].copyWith(folderId: folderId);
      _save();
    }
  }

  Future<void> moveToFolderBatch(List<String> ids, String? folderId) async {
    for (final id in ids) {
      await moveToFolder(id, folderId);
    }
  }

  // ======================== Folder CRUD ========================

  Future<MemeFolder> createFolder(String name) async {
    final folder = MemeFolder(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    _folders.add(folder);
    _save();
    return folder;
  }

  Future<void> updateFolder(MemeFolder folder) async {
    final i = _folders.indexWhere((f) => f.id == folder.id);
    if (i != -1) {
      _folders[i] = folder;
      _save();
    }
  }

  Future<void> updateFolderCover(String folderId, String? coverMemeId) async {
    final i = _folders.indexWhere((f) => f.id == folderId);
    if (i != -1) {
      final folder = _folders[i];
      _folders[i] = folder.copyWith(coverMemeId: coverMemeId);
      _save();
    }
  }

  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    // 将文件夹内的表情移出
    for (var i = 0; i < _memes.length; i++) {
      if (_memes[i].folderId == id) {
        _memes[i] = _memes[i].copyWith(folderId: null);
      }
    }
    _save();
  }

  // ======================== Settings ========================

  Map<String, String> _settings = {};
  bool _settingsLoaded = false;

  String? getSetting(String key) {
    if (!_settingsLoaded) _loadSettings();
    return _settings[key];
  }

  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    await _saveSettings();
  }

  void _loadSettings() {
    if (kIsWeb) return;
    final file = File(p.join(_basePath!, 'settings.json'));
    if (file.existsSync()) {
      try {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _settings = data.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    _settingsLoaded = true;
  }

  Future<void> _loadSettingsFromWeb() async {
    try {
      final key = _storageMode == 'shared' ? 'mako_settings_shared' : 'mako_settings_${_userId ?? 'default'}';
      final raw = await webStorageGetJson(key);
      if (raw is String && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _settings = data.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    _settingsLoaded = true;
  }

  Future<void> _saveSettings() async {
    if (kIsWeb) {
      try {
        final key = _storageMode == 'shared' ? 'mako_settings_shared' : 'mako_settings_${_userId ?? 'default'}';
        await webStorageSetJson(key, _settings);
      } catch (_) {}
      return;
    }
    try {
      await File(p.join(_basePath!, 'settings.json')).writeAsString(
        jsonEncode(_settings),
      );
    } catch (_) {}
  }

  // ======================== Export / Import ========================

  Future<String?> exportData() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final exportDir = Directory(p.join(tempDir.path, 'mako_meme_export'));
      if (await exportDir.exists()) await exportDir.delete(recursive: true);
      await exportDir.create(recursive: true);

      final memesDir = Directory(p.join(exportDir.path, 'memes'));
      await memesDir.create();

      await File(p.join(_basePath!, _metaFile)).copy(
        p.join(exportDir.path, _metaFile),
      );

      final chunkFiles = Directory(_basePath!).listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith(_memesPrefix) && p.extension(f.path) == '.json');
      for (final f in chunkFiles) {
        await f.copy(p.join(exportDir.path, p.basename(f.path)));
      }

      final srcMemesDir = Directory(p.join(_basePath!, 'memes'));
      if (await srcMemesDir.exists()) {
        await for (final f in srcMemesDir.list()) {
          if (f is File) {
            await f.copy(p.join(memesDir.path, p.basename(f.path)));
          }
        }
      }

      final zipPath = p.join(tempDir.path, 'mako_meme_backup.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(exportDir, includeDirName: false);
      await encoder.close();

      await exportDir.delete(recursive: true);
      return zipPath;
    } catch (_) {
      return null;
    }
  }

  Future<int> importZip(String zipPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory(p.join(tempDir.path, 'mako_meme_import'));
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
      await extractDir.create();

      final inputStream = InputFileStream(zipPath);
      final archiveObj = ZipDecoder().decodeStream(inputStream);

      for (final entry in archiveObj) {
        if (entry.isFile) {
          final dest = File(p.join(extractDir.path, entry.name));
          await dest.create(recursive: true);
          await dest.writeAsBytes(entry.content);
        }
      }
      inputStream.close();

      final hasMeta = await File(p.join(extractDir.path, _metaFile)).exists();
      final hasOldMemes = await File(p.join(extractDir.path, _oldMemesFile)).exists();

      if (hasMeta) {
        final data = jsonDecode(
          await File(p.join(extractDir.path, _metaFile)).readAsString(),
        ) as Map<String, dynamic>;

        final importedFolders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();

        final importedMemes = <Meme>[];
        final chunkFiles = Directory(extractDir.path).listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith(_memesPrefix) && p.extension(f.path) == '.json');
        for (final f in chunkFiles) {
          try {
            final chunkData = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
            final chunkMemes = (chunkData['memes'] as List? ?? [])
                .cast<Map<String, dynamic>>()
                .map((m) => Meme.fromMap(m))
                .toList();
            importedMemes.addAll(chunkMemes);
          } catch (_) {}
        }

        final srcImages = Directory(p.join(extractDir.path, 'memes'));
        if (await srcImages.exists()) {
          final dstImages = Directory(p.join(_basePath!, 'memes'));
          if (!await dstImages.exists()) await dstImages.create(recursive: true);
          await for (final f in srcImages.list()) {
            if (f is File) {
              await f.copy(p.join(dstImages.path, p.basename(f.path)));
            }
          }
        }

        _memes = importedMemes;
        _folders = importedFolders;
        _save();
        await extractDir.delete(recursive: true);
        return 0;
      }

      if (hasOldMemes) {
        final data = jsonDecode(
          await File(p.join(extractDir.path, _oldMemesFile)).readAsString(),
        ) as Map<String, dynamic>;

        final importedMemes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        final importedFolders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();

        final srcImages = Directory(p.join(extractDir.path, 'memes'));
        if (await srcImages.exists()) {
          final dstImages = Directory(p.join(_basePath!, 'memes'));
          if (!await dstImages.exists()) await dstImages.create(recursive: true);
          await for (final f in srcImages.list()) {
            if (f is File) {
              await f.copy(p.join(dstImages.path, p.basename(f.path)));
            }
          }
        }

        _memes = importedMemes;
        _folders = importedFolders;
        _save();
        await extractDir.delete(recursive: true);
        return 0;
      }

      final imagesDir = Directory(p.join(extractDir.path, 'memes'));
      if (await imagesDir.exists()) {
        int count = 0;
        await for (final f in imagesDir.list()) {
          if (f is File) {
            final ext = p.extension(f.path).toLowerCase();
            if (['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(ext)) {
              final id = _uuid.v4();
              final fileName = '$id$ext';
              final filePath = 'memes/$fileName';
              final dest = File(p.join(_basePath!, filePath));
              await dest.create(recursive: true);
              await f.copy(dest.path);
              _memes.insert(0, Meme(
                id: id,
                name: p.basenameWithoutExtension(p.basename(f.path)),
                filePath: filePath,
                createdAt: DateTime.now(),
                mimeType: _guessMime(ext),
                fileSize: await f.length(),
                type: _guessType(ext),
              ));
              count++;
            }
          }
        }
        _save();
        await extractDir.delete(recursive: true);
        return count;
      }

      await extractDir.delete(recursive: true);
      return -1;
    } catch (_) {
      return -1;
    }
  }

  // ======================== Utility ========================

  /// 同步 meme 到 WebDAV
  Future<bool> syncToWebDav(Meme meme, Uint8List? bytes, WebDavService webDavService) async {
    if (bytes == null || webDavService.baseUrl.isEmpty) return false;
    
    final remotePath = webDavService.generateRemotePath(meme.filePath);
    final success = await webDavService.uploadFile(remotePath, bytes);
    
    if (success) {
      // 更新 meme 的 remotePath
      final idx = _memes.indexWhere((m) => m.id == meme.id);
      if (idx != -1) {
        _memes[idx] = _memes[idx].copyWith(remotePath: remotePath);
        _save();
      }
    }
    
    return success;
  }

  /// 从 WebDAV 下载 meme 文件
  Future<Uint8List?> downloadFromWebDav(String remotePath, WebDavService webDavService) async {
    return await webDavService.downloadFile(remotePath);
  }

  String _guessMime(String ext) {
    switch (ext) {
      case '.png': return 'image/png';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      case '.bmp': return 'image/bmp';
      default: return 'image/png';
    }
  }

  String _guessExt(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return '.png';
    return fileName.substring(dot).toLowerCase();
  }

  String _guessType(String ext) {
    if (ext == '.gif') return Meme.typeGif;
    return Meme.typeImage;
  }
}
