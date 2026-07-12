import 'dart:convert';
import 'dart:io';
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

/// 图片宽高信息
class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);

  /// 宽高比（width / height）
  double get ratio => height == 0 ? 0 : width / height;

  @override
  String toString() => '${width}x$height';
}

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
        final Map<String, dynamic> data = jsonDecode(raw);
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
        final Map<String, dynamic> data = jsonDecode(await oldMemes.readAsString());
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
        final Map<String, dynamic> data = jsonDecode(await oldMeta.readAsString());
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
              final Map<String, dynamic> chunkData = jsonDecode(f.readAsStringSync());
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

  // ======================== 辅助方法 ========================

  Map<String, dynamic>? _castMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  // ======================== Meme CRUD ========================

  List<Meme> getAllMemes() {
    if (_memeBox == null) return [];
    final memes = <Meme>[];
    for (var i = 0; i < _memeBox!.length; i++) {
      final key = _memeBox!.keyAt(i);
      final value = _memeBox!.get(key);
      final map = _castMap(value);
      if (map != null) {
        memes.add(Meme.fromMap(map));
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
      final map = _castMap(value);
      if (map != null) {
        folders.add(MemeFolder.fromMap(map));
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

  /// 流式计算文件 MD5，避免一次性载入超大文件导致 OOM
  Future<String?> _computeFileHash(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final digest = await md5.bind(file.openRead()).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Meme?> _findByHash(String hash) async {
    if (_hashBox == null || _memeBox == null) return null;
    final memeId = _hashBox!.get(hash) as String?;
    if (memeId == null) return null;
    final value = _memeBox!.get(memeId);
    final map = _castMap(value);
    if (map == null) return null;
    return Meme.fromMap(map);
  }

  Future<Meme> importFile(PlatformFile file, {String? folderId, String? type, bool autoClassify = false, double classifyRatio = 1.1}) async {
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
        final b = file.bytes!;
        bytes = b;
        fileHash = _computeHash(b);
        await dest.writeAsBytes(b);
      }
    }

    if (fileHash != null) {
      final existing = await _findByHash(fileHash);
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
        // 用流式读取，避免一次性载入超大文件导致 OOM
        final sourcePath = kIsWeb ? null : (file.path ?? p.join(_basePath!, filePath));
        if (sourcePath != null) {
          characterData = await CharacterCardService.parseFromPath(sourcePath);
        }
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

    var meme = Meme(
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

    // 自动按画幅归类：正方形→表情，长方形→图片
    int imgWidth = 0;
    int imgHeight = 0;
    if (autoClassify && type == null && memeType != Meme.typeCharacterCard && ext != '.gif') {
      double? ratio;
      if (!kIsWeb) {
        final dims = await getImageDimensions(filePath);
        if (dims != null) {
          imgWidth = dims.width;
          imgHeight = dims.height;
          ratio = dims.ratio;
        }
      } else if (bytes != null) {
        final dims = _parseImageDimensionsFromHeader(bytes);
        if (dims != null) {
          imgWidth = dims.width;
          imgHeight = dims.height;
          ratio = dims.ratio;
        }
      }
      if (ratio != null && ratio > 0) {
        // 宽高比 <= 阈值 → 正方形 → 表情；否则 → 图片
        final autoType = (ratio <= classifyRatio) ? Meme.typeEmoji : Meme.typeImage;
        if (autoType != memeType) {
          await setMemeType(id, autoType);
          meme = meme.copyWith(type: autoType);
        }
      }
    } else if (meme.isImageType && meme.filePath.isNotEmpty) {
      // 非自动归类场景也解析宽高并存储
      if (!kIsWeb) {
        final dims = await getImageDimensions(filePath);
        if (dims != null) {
          imgWidth = dims.width;
          imgHeight = dims.height;
        }
      } else if (bytes != null) {
        final dims = _parseImageDimensionsFromHeader(bytes);
        if (dims != null) {
          imgWidth = dims.width;
          imgHeight = dims.height;
        }
      }
    }
    if (imgWidth > 0 && imgHeight > 0) {
      meme = meme.copyWith(width: imgWidth, height: imgHeight);
      await _saveMeme(meme, fileHash);
    }

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

  /// 获取 meme 文件的绝对路径（仅原生端有效）
  String? getMemeAbsolutePath(String filePath) {
    if (kIsWeb) return null;
    if (filePath.isEmpty) return null;
    return p.join(_basePath!, filePath);
  }

  /// 获取 meme 文件对象（仅原生端有效）
  File? getMemeFile(String filePath) {
    final abs = getMemeAbsolutePath(filePath);
    return abs == null ? null : File(abs);
  }

  /// 流式获取图片宽高比，不解码整图，超大图片安全
  /// 仅原生端有效；Web 端返回 null
  Future<double?> getImageAspectRatio(String filePath) async {
    final dims = await getImageDimensions(filePath);
    return dims?.ratio;
  }

  /// 流式获取图片宽高（不解码整图）
  /// 仅原生端有效；Web 端返回 null
  Future<ImageDimensions?> getImageDimensions(String filePath) async {
    if (kIsWeb) return null;
    final abs = getMemeAbsolutePath(filePath);
    if (abs == null) return null;
    try {
      final file = File(abs);
      if (!await file.exists()) return null;
      // 只读取前 64KB 用于解析 PNG/JPEG/GIF 头部
      final raf = await file.open();
      try {
        final header = await raf.read(64 * 1024);
        return _parseImageDimensionsFromHeader(header);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// 从文件头字节解析图片宽高（支持 PNG/JPEG/GIF/BMP/WEBP）
  static ImageDimensions? _parseImageDimensionsFromHeader(Uint8List bytes) {
    if (bytes.length < 12) return null;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      if (bytes.length < 24) return null;
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      if (w > 0 && h > 0) return ImageDimensions(w, h);
      return null;
    }
    // JPEG: FF D8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return _parseJpegDimensions(bytes);
    }
    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
      if (bytes.length < 10) return null;
      final w = bytes[6] | (bytes[7] << 8);
      final h = bytes[8] | (bytes[9] << 8);
      if (w > 0 && h > 0) return ImageDimensions(w, h);
      return null;
    }
    // BMP: 42 4D
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      if (bytes.length < 26) return null;
      final w = (bytes[18]) | (bytes[19] << 8) | (bytes[20] << 16) | (bytes[21] << 24);
      final h = (bytes[22]) | (bytes[23] << 8) | (bytes[24] << 16) | (bytes[25] << 24);
      if (w > 0 && h > 0) return ImageDimensions(w, h.abs());
      return null;
    }
    // WEBP: 52 49 46 46 ?? ?? ?? ?? 57 45 42 50
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      // RIFF .... WEBP
      if (bytes.length < 30) return null;
      final fourcc = String.fromCharCodes(bytes.sublist(12, 16));
      if (fourcc == 'VP8 ') {
        final w = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
        final h = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
        if (w > 0 && h > 0) return ImageDimensions(w, h);
      } else if (fourcc == 'VP8L') {
        final b0 = bytes[21];
        final b1 = bytes[22];
        final b2 = bytes[23];
        final b3 = bytes[24];
        final w = 1 + ((b1 & 0x3F) << 8 | b0);
        final h = 1 + ((b3 & 0x0F) << 10 | b2 << 2 | (b1 & 0xC0) >> 6);
        if (w > 0 && h > 0) return ImageDimensions(w, h);
      } else if (fourcc == 'VP8X') {
        final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        if (w > 0 && h > 0) return ImageDimensions(w, h);
      }
      return null;
    }
    return null;
  }

  static ImageDimensions? _parseJpegDimensions(Uint8List bytes) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) return null;
      final marker = bytes[i + 1];
      // SOFn markers: C0-CF (except C4, C8, CC)
      if (marker >= 0xC0 && marker <= 0xCF &&
          marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        if (w > 0 && h > 0) return ImageDimensions(w, h);
        return null;
      }
      // 其它 marker 跳过
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + segLen;
    }
    return null;
  }

  Future<List<Meme>> importFiles(List<PlatformFile> files, {String? folderId, bool autoClassify = false, double classifyRatio = 1.1}) async {
    final results = <Meme>[];
    for (final file in files) {
      results.add(await importFile(file, folderId: folderId, autoClassify: autoClassify, classifyRatio: classifyRatio));
    }
    return results;
  }

  Meme? _getMeme(String id) {
    if (_memeBox == null) return null;
    final value = _memeBox!.get(id);
    final map = _castMap(value);
    if (map == null) return null;
    return Meme.fromMap(map);
  }

  Future<void> reimportMeme(String memeId, PlatformFile file) async {
    if (_memeBox == null) return;
    final old = _getMeme(memeId);
    if (old == null) return;

    Uint8List? bytes;
    String? newHash;

    if (kIsWeb) {
      bytes = file.bytes;
      if (bytes != null) {
        newHash = _computeHash(bytes);
        await webStorageSetBinary(old.filePath, bytes);
      }
    } else {
      final dest = File(p.join(_basePath!, old.filePath));
      await dest.create(recursive: true);
      if (file.path != null) {
        await File(file.path!).copy(dest.path);
        newHash = await _computeFileHash(dest.path);
      } else if (file.bytes != null) {
        final b = file.bytes!;
        bytes = b;
        newHash = _computeHash(b);
        await dest.writeAsBytes(b);
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
    final meme = _getMeme(id);
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
    final meme = _getMeme(id);
    if (meme == null) return;
    await _memeBox!.put(id, meme.copyWith(name: newName).toMap());
  }

  Future<void> setMemeType(String id, String type) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    await _memeBox!.put(id, meme.copyWith(type: type).toMap());
  }

  Future<void> updateCharacterData(String id, Map<String, dynamic> data) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    await _memeBox!.put(id, meme.copyWith(characterData: data).toMap());
  }

  Future<void> toggleFavorite(String id) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    await _memeBox!.put(id, meme.copyWith(isFavorite: !meme.isFavorite).toMap());
  }

  Future<void> moveToFolder(String memeId, String? folderId) async {
    if (_memeBox == null) return;
    final meme = _getMeme(memeId);
    if (meme == null) return;
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
    if (_folderBox == null) return;
    final value = _folderBox!.get(folderId);
    final map = _castMap(value);
    if (map == null) return;
    final folder = MemeFolder.fromMap(map);
    final updated = coverMemeId == null
        ? MemeFolder(
            id: folder.id,
            name: folder.name,
            createdAt: folder.createdAt,
            colorValue: folder.colorValue,
          )
        : folder.copyWith(coverMemeId: coverMemeId);
    await _folderBox!.put(folderId, updated.toMap());
  }

  Future<void> deleteFolder(String id) async {
    if (_folderBox == null || _memeBox == null) return;
    await _folderBox!.delete(id);

    final folderMemes = <String>[];
    for (var i = 0; i < _memeBox!.length; i++) {
      final key = _memeBox!.keyAt(i);
      final value = _memeBox!.get(key);
      final map = _castMap(value);
      if (map != null && map['folderId'] == id) {
        folderMemes.add(key);
      }
    }
    for (final memeId in folderMemes) {
      final meme = _getMeme(memeId);
      if (meme != null) {
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
        final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
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
        final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
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
        final Map<String, dynamic> data = jsonDecode(raw);
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

  /// 导出数据为 zip。
  /// - 原生端：返回临时文件路径
  /// - Web 端：返回 null，改用 [exportDataBytes] 获取字节数组
  Future<String?> exportData() async {
    if (kIsWeb) return null;
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
      // 逐个添加文件，避免 addDirectory API 差异
      await for (final entity in exportDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relPath = p.relative(entity.path, from: exportDir.path);
          await encoder.addFile(entity, relPath);
        }
      }
      await encoder.close();

      await exportDir.delete(recursive: true);
      return zipPath;
    } catch (e) {
      return null;
    }
  }

  /// 导出数据为 zip 字节数组（用于 Web 端下载）
  Future<Uint8List?> exportDataBytes() async {
    try {
      final folders = getAllFolders();
      final allMemes = getAllMemes();

      final archive = Archive();

      // meta.json
      final meta = {
        'version': 4,
        'format': 'jsonl',
        'folders': folders.map((f) => f.toMap()).toList(),
        'meme_count': allMemes.length,
      };
      archive.addFile(ArchiveFile.bytes(
        'meta.json',
        Uint8List.fromList(utf8.encode(jsonEncode(meta))),
      ));

      // memes.jsonl
      final jsonlBuf = StringBuffer();
      for (final meme in allMemes) {
        jsonlBuf.writeln(jsonEncode(meme.toMap()));
      }
      archive.addFile(ArchiveFile.bytes(
        'memes.jsonl',
        Uint8List.fromList(utf8.encode(jsonlBuf.toString())),
      ));

      // memes/ 图片文件
      for (final meme in allMemes) {
        if (meme.filePath.isEmpty) continue;
        Uint8List? bytes;
        if (kIsWeb) {
          bytes = await webStorageGetBinary(meme.filePath);
        } else {
          final f = getMemeFile(meme.filePath);
          if (f != null && await f.exists()) {
            bytes = await f.readAsBytes();
          }
        }
        if (bytes != null) {
          archive.addFile(ArchiveFile.bytes('memes/${meme.filePath}', bytes));
        }
      }

      final zipBytes = ZipEncoder().encode(archive);
      return Uint8List.fromList(zipBytes);
    } catch (e) {
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
              // 直接用 path 流式拷贝，避免一次性读取超大文件导致 OOM
              final platformFile = PlatformFile(
                name: p.basename(f.path),
                size: await f.length(),
                path: f.path,
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
        final Map<String, dynamic> metaData = jsonDecode(await metaFile.readAsString());
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
          final Map<String, dynamic> data = jsonDecode(line);
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
        final Map<String, dynamic> data = jsonDecode(await oldMemesFile.readAsString());
        importedMemes = (data['memes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((m) => Meme.fromMap(m))
            .toList();
        importedFolders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();
      } else if (await metaFile.exists()) {
        final Map<String, dynamic> data = jsonDecode(await metaFile.readAsString());
        importedFolders = (data['folders'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map((f) => MemeFolder.fromMap(f))
            .toList();

        final chunkFiles = extractDir.listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('memes_') && p.extension(f.path) == '.json');
        for (final f in chunkFiles) {
          try {
            final Map<String, dynamic> chunkData = jsonDecode(f.readAsStringSync());
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
      final m = _getMeme(meme.id);
      if (m != null) {
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
