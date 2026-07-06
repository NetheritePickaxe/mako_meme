import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:archive/archive_io.dart';
import 'package:hive/hive.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import 'character_card_service.dart';
import 'storage_platform.dart';
import 'webdav_service.dart';
import 'admin_service.dart';

/// Hive 数据库存储 — 跨平台，Web 上使用 IndexedDB
class StorageService {
  final Uuid _uuid = const Uuid();
  Box? _memeBox;
  Box? _folderBox;
  Box? _hashBox;
  String? _basePath;
  String? _userId;
  String _storageMode = 'personal';

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
    } else {
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
      Hive.init(p.join(_basePath!, 'hive'));
      await _openBoxes();
      await _migrateFromJsonIfNeeded();
    }
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

  // ======================== Hive 初始化 ========================

  Future<void> _openBoxes() async {
    final boxName = _storageMode == 'shared' ? 'shared' : _userId ?? 'default';
    _memeBox = await Hive.openBox('memes_$boxName');
    _folderBox = await Hive.openBox('folders_$boxName');
    _hashBox = await Hive.openBox('hashes_$boxName');
  }

  // ======================== Web 存储 ========================

  Future<void> _initWeb() async {
    try {
      await initWebStorage();
      Hive.init('mako_meme_hive');
      await _openBoxes();
      await _migrateWebFromIndexedDB();
      await _loadSettingsFromWeb();
    } catch (_) {}
  }

  Future<void> _migrateWebFromIndexedDB() async {
    if (_memeBox == null) return;
    if (_memeBox!.isNotEmpty) return;

    try {
      final key = _storageMode == 'shared' ? 'mako_memes_shared' : 'mako_memes_${_userId ?? 'default'}';
      final raw = await webStorageGetJson(key);
      if (raw != null && raw is String) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final memes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        final folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();

        for (final folder in folders) {
          await _folderBox!.put(folder.id, folder.toMap());
        }
        for (final meme in memes) {
          await _memeBox!.put(meme.id, meme.toMap());
        }
      }
    } catch (_) {}
  }

  // ======================== 从旧 JSON 迁移 ========================

  Future<void> _migrateFromJsonIfNeeded() async {
    if (_memeBox == null) return;
    if (_memeBox!.isNotEmpty) return;

    final oldMeta = File(p.join(_basePath!, 'meta.json'));
    final oldMemes = File(p.join(_basePath!, 'memes.json'));

    List<Meme> memes = [];
    List<MemeFolder> folders = [];

    if (await oldMemes.exists()) {
      try {
        final data = jsonDecode(await oldMemes.readAsString()) as Map<String, dynamic>;
        memes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      } catch (_) {}
    } else if (await oldMeta.exists()) {
      try {
        final data = jsonDecode(await oldMeta.readAsString()) as Map<String, dynamic>;
        folders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();

        final dir = Directory(_basePath!);
        if (await dir.exists()) {
          final files = dir.listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('memes_') && p.extension(f.path) == '.json')
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

          for (final f in files) {
            try {
              final chunkData = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
              final chunkMemes = (chunkData['memes'] as List? ?? [])
                  .cast<Map<String, dynamic>>()
                  .map((m) => Meme.fromMap(m))
                  .toList();
              memes.addAll(chunkMemes);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (memes.isEmpty && folders.isEmpty) return;

    for (final folder in folders) {
      await _folderBox!.put(folder.id, folder.toMap());
    }
    for (final meme in memes) {
      await _memeBox!.put(meme.id, meme.toMap());
    }

    try {
      if (await oldMemes.exists()) {
        await oldMemes.rename('${oldMemes.path}.bak');
      }
      if (await oldMeta.exists()) {
        await oldMeta.rename('${oldMeta.path}.bak');
      }
    } catch (_) {}
  }

  // ======================== Meme CRUD ========================

  List<Meme> getAllMemes() {
    if (_memeBox == null) return [];
    final memes = <Meme>[];
    for (var i = 0; i < _memeBox!.length; i++) {
      final key = _memeBox!.keyAt(i);
      final value = _memeBox!.get(key);
      if (value is Map) {
        memes.add(Meme.fromMap(Map<String, dynamic>.from(value as Map)));
      } else if (value is Map<String, dynamic>) {
        memes.add(Meme.fromMap(value));
      }
    }
    memes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return memes;
  }

  List<MemeFolder> getAllFolders() {
    if (_folderBox == null) return [];
    final folders = <MemeFolder>[];
    for (var i = 0; i < _folderBox!.length; i++) {
      final key = _folderBox!.keyAt(i);
      final value = _folderBox!.get(key);
      if (value is Map) {
        folders.add(MemeFolder.fromMap(Map<String, dynamic>.from(value as Map)));
      } else if (value is Map<String, dynamic>) {
        folders.add(MemeFolder.fromMap(value));
      }
    }
    folders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return folders;
  }

  String getFullMemePath(String relPath) {
    if (kIsWeb) return relPath;
    final base = _basePath;
    if (base == null) return relPath;
    return p.join(base, relPath);
  }

  // ======================== 导入 / 去重 ========================

  String _computeHash(Uint8List bytes) {
    return md5.convert(bytes).toString();
  }

  Future<String?> _computeFileHash(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      return _computeHash(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Meme?> _findByHash(String hash) async {
    if (_hashBox == null || _memeBox == null) return null;
    final memeId = _hashBox!.get(hash) as String?;
    if (memeId == null) return null;
    final value = _memeBox!.get(memeId);
    if (value == null) return null;
    if (value is Map<String, dynamic>) return Meme.fromMap(value);
    if (value is Map) return Meme.fromMap(Map<String, dynamic>.from(value as Map));
    return null;
  }

  Future<Meme> importFile(PlatformFile file, {String? folderId, String? type}) async {
    final id = _uuid.v4();
    final ext = _guessExt(file.name);
    final fileName = '$id$ext';
    final now = DateTime.now();

    Uint8List? bytes;
    String filePath;
    String? fileHash;

    if (kIsWeb) {
      bytes = file.bytes;
      filePath = 'memes/$fileName';
      if (bytes != null) {
        fileHash = _computeHash(bytes);
        await webStorageSetBinary(filePath, bytes);
      }
    } else {
      filePath = 'memes/$fileName';
      final dest = File(p.join(_basePath!, filePath));
      await dest.create(recursive: true);
      if (file.path != null) {
        await File(file.path!).copy(dest.path);
        fileHash = await _computeFileHash(dest.path);
      } else if (file.bytes != null) {
        bytes = file.bytes;
        fileHash = _computeHash(bytes!);
        await dest.writeAsBytes(bytes);
      }
    }

    if (fileHash != null) {
      final existing = await _findByHash(fileHash!);
      if (existing != null) {
        if (!kIsWeb) {
          final dest = File(p.join(_basePath!, filePath));
          if (await dest.exists()) await dest.delete();
        } else if (filePath.isNotEmpty) {
          await webStorageDelete(filePath);
        }
        return existing;
      }
    }

    String memeType = type ?? _guessType(ext);
    Map<String, dynamic>? characterData;

    if (ext == '.png') {
      if (bytes != null) {
        characterData = await CharacterCardService.parseFromBytes(bytes);
      } else if (file.path != null) {
        characterData = await CharacterCardService.parseFromPath(file.path!);
      }

      if (CharacterCardService.isValidCharacterCard(characterData)) {
        memeType = Meme.typeCharacterCard;
        final cardName = CharacterCardService.getName(characterData!);
        if (cardName.isNotEmpty && cardName != '未知角色') {
          final meme = Meme(
            id: id,
            name: cardName,
            filePath: filePath,
            folderId: folderId,
            tags: [],
            createdAt: now,
            mimeType: _guessMime(ext),
            fileSize: bytes?.length ?? file.size,
            type: memeType,
            characterData: CharacterCardService.sanitizeCard(characterData),
          );
          await _saveMeme(meme, fileHash);
          return meme;
        }
      }
    }

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
      characterData: characterData != null ? CharacterCardService.sanitizeCard(characterData) : null,
    );
    await _saveMeme(meme, fileHash);
    return meme;
  }

  Future<void> _saveMeme(Meme meme, String? fileHash) async {
    if (_memeBox == null) return;
    await _memeBox!.put(meme.id, meme.toMap());
    if (fileHash != null && _hashBox != null) {
      await _hashBox!.put(fileHash, meme.id);
    }
  }

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

  Future<void> reimportMeme(String memeId, PlatformFile file) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(memeId);
    if (value == null) return;
    Meme old;
    if (value is Map<String, dynamic>) {
      old = Meme.fromMap(value);
    } else if (value is Map) {
      old = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    } else {
      return;
    }

    Uint8List? bytes;
    String? newHash;

    if (kIsWeb) {
      bytes = file.bytes;
      if (bytes != null) {
        newHash = _computeHash(bytes);
        await webStorageSetBinary(old.filePath, bytes!);
      }
    } else {
      final dest = File(p.join(_basePath!, old.filePath));
      await dest.create(recursive: true);
      if (file.path != null) {
        await File(file.path!).copy(dest.path);
        newHash = await _computeFileHash(dest.path);
      } else if (file.bytes != null) {
        bytes = file.bytes;
        newHash = _computeHash(bytes!);
        await dest.writeAsBytes(bytes);
      }
    }

    if (_hashBox != null && old.filePath.isNotEmpty && !kIsWeb) {
      final oldHash = await _computeFileHash(p.join(_basePath!, old.filePath));
      if (oldHash != null) {
        await _hashBox!.delete(oldHash);
      }
    }

    final updated = old.copyWith(
      mimeType: _guessMime(_guessExt(file.name)),
      fileSize: file.size,
    );
    await _memeBox!.put(memeId, updated.toMap());
    if (newHash != null && _hashBox != null) {
      await _hashBox!.put(newHash, memeId);
    }
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
    await _saveMeme(meme, null);
    return meme;
  }

  Future<void> deleteMeme(String id) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(id);
    Meme? meme;
    if (value is Map<String, dynamic>) {
      meme = Meme.fromMap(value);
    } else if (value is Map) {
      meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    }
    if (meme == null) return;

    if (!kIsWeb && meme.filePath.isNotEmpty) {
      final file = File(p.join(_basePath!, meme.filePath));
      if (await file.exists()) await file.delete();
    }
    if (kIsWeb && meme.filePath.isNotEmpty) {
      await webStorageDelete(meme.filePath);
    }

    await _memeBox!.delete(id);
    if (_hashBox != null && meme.filePath.isNotEmpty && !kIsWeb) {
      final fullPath = p.join(_basePath!, meme.filePath);
      final hash = await _computeFileHash(fullPath);
      if (hash != null) {
        await _hashBox!.delete(hash);
      }
    }
  }

  Future<void> deleteMemes(List<String> ids) async {
    for (final id in ids) {
      await deleteMeme(id);
    }
  }

  Future<void> renameMeme(String id, String newName) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(id);
    Meme meme;
    if (value is Map<String, dynamic>) {
      meme = Meme.fromMap(value);
    } else if (value is Map) {
      meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    } else {
      return;
    }
    await _memeBox!.put(id, meme.copyWith(name: newName).toMap());
  }

  Future<void> setMemeType(String id, String type) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(id);
    Meme meme;
    if (value is Map<String, dynamic>) {
      meme = Meme.fromMap(value);
    } else if (value is Map) {
      meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    } else {
      return;
    }
    await _memeBox!.put(id, meme.copyWith(type: type).toMap());
  }

  Future<void> updateCharacterData(String id, Map<String, dynamic> data) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(id);
    Meme meme;
    if (value is Map<String, dynamic>) {
      meme = Meme.fromMap(value);
    } else if (value is Map) {
      meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    } else {
      return;
    }
    await _memeBox!.put(id, meme.copyWith(characterData: data).toMap());
  }

  Future<void> toggleFavorite(String id) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(id);
    Meme meme;
    if (value is Map<String, dynamic>) {
      meme = Meme.fromMap(value);
    } else if (value is Map) {
      meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    } else {
      return;
    }
    await _memeBox!.put(id, meme.copyWith(isFavorite: !meme.isFavorite).toMap());
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    if (_memeBox == null) return;
    final value = _memeBox!.get(memeId);
    Meme meme;
    if (value is Map<String, dynamic>) {
      meme = Meme.fromMap(value);
    } else if (value is Map) {
      meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
    } else {
      return;
    }
    await _memeBox!.put(memeId, meme.copyWith(folderId: folderId).toMap());
  }

  Future<void> moveToFolderBatch(List<String> ids, String? folderId) async {
    for (final id in ids) {
      await moveToFolder(id, folderId);
    }
  }

  // ======================== Folder CRUD ========================

  Future<MemeFolder> createFolder(String name) async {
    if (_folderBox == null) {
      return MemeFolder(id: _uuid.v4(), name: name, createdAt: DateTime.now());
    }
    final folder = MemeFolder(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    await _folderBox!.put(folder.id, folder.toMap());
    return folder;
  }

  Future<void> updateFolder(MemeFolder folder) async {
    if (_folderBox == null) return;
    await _folderBox!.put(folder.id, folder.toMap());
  }

  Future<void> updateFolderCover(String folderId, String? coverMemeId) async {
    // coverMemeId 不存储在 folder 表中，保持接口兼容
  }

  Future<void> deleteFolder(String id) async {
    if (_folderBox == null || _memeBox == null) return;
    await _folderBox!.delete(id);

    final folderMemes = <String>[];
    for (var i = 0; i < _memeBox!.length; i++) {
      final key = _memeBox!.keyAt(i);
      final value = _memeBox!.get(key);
      Map<String, dynamic>? map;
      if (value is Map<String, dynamic>) {
        map = value;
      } else if (value is Map) {
        map = Map<String, dynamic>.from(value as Map);
      }
      if (map != null && map['folderId'] == id) {
        folderMemes.add(key);
      }
    }
    for (final memeId in folderMemes) {
      final value = _memeBox!.get(memeId);
      if (value is Map<String, dynamic>) {
        final meme = Meme.fromMap(value);
        await _memeBox!.put(memeId, meme.copyWith(folderId: null).toMap());
      } else if (value is Map) {
        final meme = Meme.fromMap(Map<String, dynamic>.from(value as Map));
        await _memeBox!.put(memeId, meme.copyWith(folderId: null).toMap());
      }
    }
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

  Future<void> _loadSettingsEarly() async {
    if (_settingsLoaded) return;
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

      final folders = getAllFolders();
      final allMemes = getAllMemes();

      final meta = {
        'version': 4,
        'format': 'jsonl',
        'folders': folders.map((f) => f.toMap()).toList(),
        'meme_count': allMemes.length,
      };
      await File(p.join(exportDir.path, 'meta.json')).writeAsString(jsonEncode(meta));

      final jsonlFile = File(p.join(exportDir.path, 'memes.jsonl'));
      final sink = jsonlFile.openWrite();
      for (final meme in allMemes) {
        sink.writeln(jsonEncode(meme.toMap()));
      }
      await sink.flush();
      await sink.close();

      final srcMemesDir = Directory(p.join(_basePath!, 'memes'));
      if (kIsWeb) {
        for (final meme in allMemes) {
          if (meme.filePath.isEmpty) continue;
          final bytes = await webStorageGetBinary(meme.filePath);
          if (bytes != null) {
            final dest = File(p.join(exportDir.path, meme.filePath));
            await dest.create(recursive: true);
            await dest.writeAsBytes(bytes);
          }
        }
      } else if (await srcMemesDir.exists()) {
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

      final jsonlFile = File(p.join(extractDir.path, 'memes.jsonl'));
      final metaFile = File(p.join(extractDir.path, 'meta.json'));
      final oldMemesFile = File(p.join(extractDir.path, 'memes.json'));

      if (await jsonlFile.exists()) {
        return await _importFromJsonl(extractDir);
      } else if (await metaFile.exists() || await oldMemesFile.exists()) {
        return await _importFromOldFormat(extractDir);
      }

      final imagesDir = Directory(p.join(extractDir.path, 'memes'));
      if (await imagesDir.exists()) {
        int count = 0;
        await for (final f in imagesDir.list()) {
          if (f is File) {
            final ext = p.extension(f.path).toLowerCase();
            if (['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(ext)) {
              final bytes = await f.readAsBytes();
              final platformFile = PlatformFile(
                name: p.basename(f.path),
                size: await f.length(),
                path: f.path,
                bytes: bytes,
              );
              await importFile(platformFile);
              count++;
            }
          }
        }
        await extractDir.delete(recursive: true);
        return count;
      }

      await extractDir.delete(recursive: true);
      return -1;
    } catch (_) {
      return -1;
    }
  }

  Future<int> _importFromJsonl(Directory extractDir) async {
    try {
      final metaFile = File(p.join(extractDir.path, 'meta.json'));
      List<MemeFolder> importedFolders = [];

      if (await metaFile.exists()) {
        final metaData = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        importedFolders = (metaData['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      }

      final importedMemes = <Meme>[];
      final jsonlFile = File(p.join(extractDir.path, 'memes.jsonl'));
      final lines = await jsonlFile.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          importedMemes.add(Meme.fromMap(data));
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

      if (_folderBox != null) {
        for (final folder in importedFolders) {
          if (!_folderBox!.containsKey(folder.id)) {
            await _folderBox!.put(folder.id, folder.toMap());
          }
        }
      }

      int addedCount = 0;
      for (final meme in importedMemes) {
        if (_memeBox != null && !_memeBox!.containsKey(meme.id)) {
          String? fileHash;
          if (meme.filePath.isNotEmpty && !kIsWeb) {
            final fullPath = p.join(_basePath!, meme.filePath);
            if (await File(fullPath).exists()) {
              fileHash = await _computeFileHash(fullPath);
            }
          }
          await _saveMeme(meme, fileHash);
          addedCount++;
        }
      }

      await extractDir.delete(recursive: true);
      return addedCount;
    } catch (_) {
      return -1;
    }
  }

  Future<int> _importFromOldFormat(Directory extractDir) async {
    try {
      List<Meme> importedMemes = [];
      List<MemeFolder> importedFolders = [];

      final metaFile = File(p.join(extractDir.path, 'meta.json'));
      final oldMemesFile = File(p.join(extractDir.path, 'memes.json'));

      if (await oldMemesFile.exists()) {
        final data = jsonDecode(await oldMemesFile.readAsString()) as Map<String, dynamic>;
        importedMemes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        importedFolders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      } else if (await metaFile.exists()) {
        final data = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        importedFolders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();

        final chunkFiles = extractDir.listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('memes_') && p.extension(f.path) == '.json');
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

      if (_folderBox != null) {
        for (final folder in importedFolders) {
          if (!_folderBox!.containsKey(folder.id)) {
            await _folderBox!.put(folder.id, folder.toMap());
          }
        }
      }

      int addedCount = 0;
      for (final meme in importedMemes) {
        if (_memeBox != null && !_memeBox!.containsKey(meme.id)) {
          String? fileHash;
          if (meme.filePath.isNotEmpty && !kIsWeb) {
            final fullPath = p.join(_basePath!, meme.filePath);
            if (await File(fullPath).exists()) {
              fileHash = await _computeFileHash(fullPath);
            }
          }
          await _saveMeme(meme, fileHash);
          addedCount++;
        }
      }

      await extractDir.delete(recursive: true);
      return addedCount;
    } catch (_) {
      return -1;
    }
  }

  // ======================== Utility ========================

  Future<bool> syncToWebDav(Meme meme, Uint8List? bytes, WebDavService webDavService) async {
    if (bytes == null || webDavService.baseUrl.isEmpty) return false;

    final remotePath = webDavService.generateRemotePath(meme.filePath);
    final success = await webDavService.uploadFile(remotePath, bytes);

    if (success && _memeBox != null) {
      final value = _memeBox!.get(meme.id);
      if (value != null) {
        Meme m;
        if (value is Map<String, dynamic>) {
          m = Meme.fromMap(value);
        } else if (value is Map) {
          m = Meme.fromMap(Map<String, dynamic>.from(value as Map));
        } else {
          return success;
        }
        await _memeBox!.put(meme.id, m.copyWith(remotePath: remotePath).toMap());
      }
    }

    return success;
  }

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
