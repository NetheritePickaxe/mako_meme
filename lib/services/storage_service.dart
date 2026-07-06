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
import 'package:isar/isar.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import '../models/isar_meme.dart';
import 'character_card_service.dart';
import 'storage_platform.dart';
import 'webdav_service.dart';
import 'admin_service.dart';

/// Isar 数据库存储 — 跨平台，Web 上使用 IndexedDB
class StorageService {
  final Uuid _uuid = const Uuid();
  Isar? _isar;
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
      await _initIsar();
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

  // ======================== Isar 初始化 ========================

  Future<void> _initIsar() async {
    if (kIsWeb) {
      _isar = await Isar.open(
        [IsarMemeSchema, IsarFolderSchema],
        name: 'mako_meme_${_userId ?? 'default'}',
      );
    } else {
      _isar = await Isar.open(
        [IsarMemeSchema, IsarFolderSchema],
        directory: _basePath!,
        name: 'mako_meme',
      );
    }
  }

  // ======================== 从旧 JSON 迁移 ========================

  Future<void> _migrateFromJsonIfNeeded() async {
    if (_isar == null) return;

    final memeCount = await _isar!.isarMemes.count();
    if (memeCount > 0) return;

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

    await _isar!.writeTxn(() async {
      for (final folder in folders) {
        final isarFolder = IsarFolder()
          ..uuid = folder.id
          ..name = folder.name
          ..createdAt = folder.createdAt;
        await _isar!.isarFolders.put(isarFolder);
      }

      for (final meme in memes) {
        final isarMeme = _memeToIsar(meme);
        await _isar!.isarMemes.put(isarMeme);
      }
    });

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
    if (_isar == null) return [];
    final results = _isar!.isarMemes.where().sortByCreatedAtDesc().findAllSync();
    return results.map(_isarToMeme).toList();
  }

  List<MemeFolder> getAllFolders() {
    if (_isar == null) return [];
    final results = _isar!.isarFolders.where().sortByCreatedAt().findAllSync();
    return results.map(_isarToFolder).toList();
  }

  String getFullMemePath(String relPath) {
    if (kIsWeb) return relPath;
    final base = _basePath;
    if (base == null) return relPath;
    return p.join(base, relPath);
  }

  IsarMeme _memeToIsar(Meme meme) {
    return IsarMeme()
      ..uuid = meme.id
      ..name = meme.name
      ..filePath = meme.filePath
      ..folderId = meme.folderId
      ..tagList = meme.tags
      ..createdAt = meme.createdAt
      ..isFavorite = meme.isFavorite
      ..mimeType = meme.mimeType
      ..fileSize = meme.fileSize
      ..type = meme.type
      ..textContent = meme.textContent
      ..remotePath = meme.remotePath
      ..characterData = meme.characterData != null ? jsonEncode(meme.characterData) : null
      ..fileHash = null;
  }

  Meme _isarToMeme(IsarMeme isarMeme) {
    return Meme(
      id: isarMeme.uuid,
      name: isarMeme.name,
      filePath: isarMeme.filePath,
      folderId: isarMeme.folderId,
      tags: isarMeme.tagList,
      createdAt: isarMeme.createdAt,
      isFavorite: isarMeme.isFavorite,
      mimeType: isarMeme.mimeType,
      fileSize: isarMeme.fileSize,
      type: isarMeme.type,
      textContent: isarMeme.textContent,
      remotePath: isarMeme.remotePath,
      characterData: isarMeme.characterData != null && isarMeme.characterData!.isNotEmpty
          ? (() {
              try {
                return jsonDecode(isarMeme.characterData!) as Map<String, dynamic>;
              } catch (_) {
                return null;
              }
            })()
          : null,
    );
  }

  IsarFolder _folderToIsar(MemeFolder folder) {
    return IsarFolder()
      ..uuid = folder.id
      ..name = folder.name
      ..createdAt = folder.createdAt;
  }

  MemeFolder _isarToFolder(IsarFolder isarFolder) {
    return MemeFolder(
      id: isarFolder.uuid,
      name: isarFolder.name,
      createdAt: isarFolder.createdAt,
    );
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

  Future<bool> _hashExists(String hash) async {
    if (_isar == null) return false;
    final count = await _isar!.isarMemes.filter().fileHashEqualTo(hash).count();
    return count > 0;
  }

  Future<Meme?> _findByHash(String hash) async {
    if (_isar == null) return null;
    final result = _isar!.isarMemes.filter().fileHashEqualTo(hash).findFirstSync();
    if (result == null) return null;
    return _isarToMeme(result);
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
          await _saveMemeToIsar(meme, fileHash);
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
    await _saveMemeToIsar(meme, fileHash);
    return meme;
  }

  Future<void> _saveMemeToIsar(Meme meme, String? fileHash) async {
    if (_isar == null) return;
    await _isar!.writeTxn(() async {
      final isarMeme = _memeToIsar(meme);
      isarMeme.fileHash = fileHash;
      await _isar!.isarMemes.put(isarMeme);
    });
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
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(memeId).findFirstSync();
    if (isarMeme == null) return;

    Uint8List? bytes;
    String? newHash;

    if (kIsWeb) {
      bytes = file.bytes;
      if (bytes != null) {
        newHash = _computeHash(bytes);
        await webStorageSetBinary(isarMeme.filePath, bytes!);
      }
    } else {
      final dest = File(p.join(_basePath!, isarMeme.filePath));
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

    await _isar!.writeTxn(() async {
      isarMeme.mimeType = _guessMime(_guessExt(file.name));
      isarMeme.fileSize = file.size;
      isarMeme.fileHash = newHash;
      await _isar!.isarMemes.put(isarMeme);
    });
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
    await _saveMemeToIsar(meme, null);
    return meme;
  }

  Future<void> deleteMeme(String id) async {
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(id).findFirstSync();
    if (isarMeme == null) return;

    if (!kIsWeb && isarMeme.filePath.isNotEmpty) {
      final file = File(p.join(_basePath!, isarMeme.filePath));
      if (await file.exists()) await file.delete();
    }
    if (kIsWeb && isarMeme.filePath.isNotEmpty) {
      await webStorageDelete(isarMeme.filePath);
    }

    await _isar!.writeTxn(() async {
      await _isar!.isarMemes.delete(isarMeme.id);
    });
  }

  Future<void> deleteMemes(List<String> ids) async {
    for (final id in ids) {
      await deleteMeme(id);
    }
  }

  Future<void> renameMeme(String id, String newName) async {
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(id).findFirstSync();
    if (isarMeme == null) return;
    await _isar!.writeTxn(() async {
      isarMeme.name = newName;
      await _isar!.isarMemes.put(isarMeme);
    });
  }

  Future<void> setMemeType(String id, String type) async {
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(id).findFirstSync();
    if (isarMeme == null) return;
    await _isar!.writeTxn(() async {
      isarMeme.type = type;
      await _isar!.isarMemes.put(isarMeme);
    });
  }

  Future<void> updateCharacterData(String id, Map<String, dynamic> data) async {
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(id).findFirstSync();
    if (isarMeme == null) return;
    await _isar!.writeTxn(() async {
      isarMeme.characterData = jsonEncode(data);
      await _isar!.isarMemes.put(isarMeme);
    });
  }

  Future<void> toggleFavorite(String id) async {
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(id).findFirstSync();
    if (isarMeme == null) return;
    await _isar!.writeTxn(() async {
      isarMeme.isFavorite = !isarMeme.isFavorite;
      await _isar!.isarMemes.put(isarMeme);
    });
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    if (_isar == null) return;
    final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(memeId).findFirstSync();
    if (isarMeme == null) return;
    await _isar!.writeTxn(() async {
      isarMeme.folderId = folderId;
      await _isar!.isarMemes.put(isarMeme);
    });
  }

  Future<void> moveToFolderBatch(List<String> ids, String? folderId) async {
    for (final id in ids) {
      await moveToFolder(id, folderId);
    }
  }

  // ======================== Folder CRUD ========================

  Future<MemeFolder> createFolder(String name) async {
    if (_isar == null) {
      return MemeFolder(id: _uuid.v4(), name: name, createdAt: DateTime.now());
    }
    final folder = MemeFolder(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    await _isar!.writeTxn(() async {
      await _isar!.isarFolders.put(_folderToIsar(folder));
    });
    return folder;
  }

  Future<void> updateFolder(MemeFolder folder) async {
    if (_isar == null) return;
    final isarFolder = _isar!.isarFolders.filter().uuidEqualTo(folder.id).findFirstSync();
    if (isarFolder == null) return;
    await _isar!.writeTxn(() async {
      isarFolder.name = folder.name;
      await _isar!.isarFolders.put(isarFolder);
    });
  }

  Future<void> updateFolderCover(String folderId, String? coverMemeId) async {
    // coverMemeId 不存储在 folder 表中，保持接口兼容
  }

  Future<void> deleteFolder(String id) async {
    if (_isar == null) return;
    final isarFolder = _isar!.isarFolders.filter().uuidEqualTo(id).findFirstSync();
    if (isarFolder == null) return;

    await _isar!.writeTxn(() async {
      final folderMemes = _isar!.isarMemes.filter().folderIdEqualTo(id).findAllSync();
      for (final m in folderMemes) {
        m.folderId = null;
      }
      await _isar!.isarMemes.putAll(folderMemes);
      await _isar!.isarFolders.delete(isarFolder.id);
    });
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

      await File(p.join(exportDir.path, 'folders.json')).writeAsString(
        jsonEncode({
          'version': 3,
          'folders': folders.map((f) => f.toMap()).toList(),
        }),
      );

      for (final folder in folders) {
        final folderMemes = allMemes.where((m) => m.folderId == folder.id).toList();
        final safeName = folder.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        await File(p.join(exportDir.path, '$safeName.json')).writeAsString(
          jsonEncode({
            'folder_id': folder.id,
            'folder_name': folder.name,
            'memes': folderMemes.map((m) => m.toMap()).toList(),
          }),
        );
      }

      final uncategorized = allMemes.where((m) => m.folderId == null).toList();
      if (uncategorized.isNotEmpty) {
        await File(p.join(exportDir.path, '未分类.json')).writeAsString(
          jsonEncode({
            'folder_id': null,
            'folder_name': '未分类',
            'memes': uncategorized.map((m) => m.toMap()).toList(),
          }),
        );
      }

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

      final foldersFile = File(p.join(extractDir.path, 'folders.json'));
      final metaFile = File(p.join(extractDir.path, 'meta.json'));
      final oldMemesFile = File(p.join(extractDir.path, 'memes.json'));

      if (await foldersFile.exists()) {
        return await _importFromFolderJson(extractDir);
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

  Future<int> _importFromFolderJson(Directory extractDir) async {
    try {
      final foldersData = jsonDecode(
        await File(p.join(extractDir.path, 'folders.json')).readAsString(),
      ) as Map<String, dynamic>;

      final importedFolders = (foldersData['folders'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map((f) => MemeFolder.fromMap(f))
          .toList();

      final importedMemes = <Meme>[];
      final jsonFiles = extractDir.listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.json' && p.basename(f.path) != 'folders.json')
          .toList();

      for (final f in jsonFiles) {
        try {
          final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          if (data.containsKey('memes')) {
            final chunkMemes = (data['memes'] as List? ?? [])
                .cast<Map<String, dynamic>>()
                .map((m) => Meme.fromMap(m))
                .toList();
            importedMemes.addAll(chunkMemes);
          }
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

      if (_isar != null) {
        await _isar!.writeTxn(() async {
          for (final folder in importedFolders) {
            final existing = _isar!.isarFolders.filter().uuidEqualTo(folder.id).findFirstSync();
            if (existing == null) {
              await _isar!.isarFolders.put(_folderToIsar(folder));
            }
          }

          for (final meme in importedMemes) {
            final existing = _isar!.isarMemes.filter().uuidEqualTo(meme.id).findFirstSync();
            if (existing == null) {
              final isarMeme = _memeToIsar(meme);
              if (meme.filePath.isNotEmpty && !kIsWeb) {
                final fullPath = p.join(_basePath!, meme.filePath);
                if (await File(fullPath).exists()) {
                  isarMeme.fileHash = await _computeFileHash(fullPath);
                }
              }
              await _isar!.isarMemes.put(isarMeme);
            }
          }
        });
      }

      await extractDir.delete(recursive: true);
      return importedMemes.length;
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

      if (_isar != null) {
        await _isar!.writeTxn(() async {
          for (final folder in importedFolders) {
            final existing = _isar!.isarFolders.filter().uuidEqualTo(folder.id).findFirstSync();
            if (existing == null) {
              await _isar!.isarFolders.put(_folderToIsar(folder));
            }
          }
          for (final meme in importedMemes) {
            final existing = _isar!.isarMemes.filter().uuidEqualTo(meme.id).findFirstSync();
            if (existing == null) {
              await _isar!.isarMemes.put(_memeToIsar(meme));
            }
          }
        });
      }

      await extractDir.delete(recursive: true);
      return importedMemes.length;
    } catch (_) {
      return -1;
    }
  }

  // ======================== Web 存储 ========================

  Future<void> _initWeb() async {
    try {
      await initWebStorage();
      await _initIsar();
      await _migrateWebFromIndexedDB();
      await _loadSettingsFromWeb();
    } catch (_) {}
  }

  Future<void> _migrateWebFromIndexedDB() async {
    if (_isar == null) return;
    final count = await _isar!.isarMemes.count();
    if (count > 0) return;

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

        await _isar!.writeTxn(() async {
          for (final folder in folders) {
            await _isar!.isarFolders.put(_folderToIsar(folder));
          }
          for (final meme in memes) {
            await _isar!.isarMemes.put(_memeToIsar(meme));
          }
        });
      }
    } catch (_) {}
  }

  // ======================== Utility ========================

  Future<bool> syncToWebDav(Meme meme, Uint8List? bytes, WebDavService webDavService) async {
    if (bytes == null || webDavService.baseUrl.isEmpty) return false;

    final remotePath = webDavService.generateRemotePath(meme.filePath);
    final success = await webDavService.uploadFile(remotePath, bytes);

    if (success && _isar != null) {
      final isarMeme = _isar!.isarMemes.filter().uuidEqualTo(meme.id).findFirstSync();
      if (isarMeme != null) {
        await _isar!.writeTxn(() async {
          isarMeme.remotePath = remotePath;
          await _isar!.isarMemes.put(isarMeme);
        });
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
