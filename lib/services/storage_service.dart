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
import 'package:image/image.dart' as img;
import '../models/meme.dart';
import '../models/folder.dart';
import 'character_card_service.dart';
import 'storage_platform.dart';
import 'webdav_service.dart';
import 'admin_service.dart';
import 'psd_service.dart';
import 'sprite_service.dart';

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

    // PSD 解析：提取合成预览 + 图层信息
    if (memeType == Meme.typePsd) {
      meme = await _processPsdImport(meme, file, bytes, fileHash);
    }

    // ICO/TIF 转 PNG：Flutter 原生不支持这两种格式，导入时转换为 PNG 缩略图
    if (const ['.ico', '.tif', '.tiff'].contains(ext)) {
      meme = await _processRasterConversion(meme, file, bytes, fileHash);
    }

    return meme;
  }

  /// 保存缩略图 PNG 字节到存储，返回存储路径
  /// native: memes/{id}_thumb.png，web: memes/{id}_thumb
  Future<String> _saveThumbPng(String memeId, Uint8List pngBytes) async {
    if (kIsWeb) {
      final thumbPath = 'memes/${memeId}_thumb';
      await webStorageSetBinary(thumbPath, pngBytes);
      return thumbPath;
    }
    final thumbPath = 'memes/${memeId}_thumb.png';
    final dest = File(p.join(_basePath!, thumbPath));
    await dest.create(recursive: true);
    await dest.writeAsBytes(pngBytes);
    return thumbPath;
  }

  /// PSD 导入后处理：解析图层，生成合成预览 PNG
  Future<Meme> _processPsdImport(
    Meme meme,
    PlatformFile file,
    Uint8List? inMemoryBytes,
    String? fileHash,
  ) async {
    try {
      Uint8List? psdBytes;
      if (inMemoryBytes != null) {
        psdBytes = inMemoryBytes;
      } else if (file.path != null && !kIsWeb) {
        psdBytes = await File(file.path!).readAsBytes();
      }
      if (psdBytes == null) return meme;

      final result = PsdService.parse(psdBytes);
      if (result == null) return meme;

      String? thumbPath;
      if (result.compositePng != null) {
        thumbPath = await _saveThumbPng(meme.id, result.compositePng!);
      }

      final updated = meme.copyWith(
        thumbPath: thumbPath,
        psdLayers: result.layers,
        width: result.width,
        height: result.height,
      );
      await _saveMeme(updated, fileHash);
      return updated;
    } catch (_) {
      return meme;
    }
  }

  /// ICO/TIF 转 PNG：Flutter Image 原生不支持解码这两种格式，
  /// 导入时用 image 包解码并转 PNG，存为 thumbPath
  Future<Meme> _processRasterConversion(
    Meme meme,
    PlatformFile file,
    Uint8List? inMemoryBytes,
    String? fileHash,
  ) async {
    try {
      Uint8List? sourceBytes;
      if (inMemoryBytes != null) {
        sourceBytes = inMemoryBytes;
      } else if (file.path != null && !kIsWeb) {
        sourceBytes = await File(file.path!).readAsBytes();
      }
      if (sourceBytes == null) return meme;

      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) return meme;

      final png = Uint8List.fromList(img.encodePng(decoded));
      final thumbPath = await _saveThumbPng(meme.id, png);

      final updated = meme.copyWith(
        thumbPath: thumbPath,
        width: decoded.width,
        height: decoded.height,
      );
      await _saveMeme(updated, fileHash);
      return updated;
    } catch (_) {
      return meme;
    }
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

  /// 公开接口：从字节头解析图片宽高（不解码整图，避免 OOM）
  static ImageDimensions? parseImageDimensionsFromHeader(Uint8List bytes) =>
      _parseImageDimensionsFromHeader(bytes);

  /// 从文件头字节解析图片宽高（支持 PNG/JPEG/GIF/BMP/WEBP/SVG）
  static ImageDimensions? _parseImageDimensionsFromHeader(Uint8List bytes) {
    if (bytes.length < 12) return null;
    // SVG: 文本 "<?xml" 或 "<svg"
    if (bytes[0] == 0x3C && (bytes[1] == 0x3F || bytes[1] == 0x73)) {
      return _parseSvgDimensions(bytes);
    }
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

  /// 解析 SVG 宽高：优先 width/height 属性，其次 viewBox
  static ImageDimensions? _parseSvgDimensions(Uint8List bytes) {
    // 仅读前 16KB，足够找到 <svg> 头部属性
    final len = bytes.length < 16 * 1024 ? bytes.length : 16 * 1024;
    final head = String.fromCharCodes(bytes.sublist(0, len));
    final svgStart = head.indexOf('<svg');
    if (svgStart < 0) return null;
    // 截到 <svg> 标签结束（首个 '>'）
    final tagEnd = head.indexOf('>', svgStart);
    final tag = tagEnd < 0 ? head.substring(svgStart) : head.substring(svgStart, tagEnd + 1);

    double? w = _parseSvgLength(_extractAttr(tag, 'width'));
    double? h = _parseSvgLength(_extractAttr(tag, 'height'));
    // 回退到 viewBox="minx miny w h"
    if ((w == null || w <= 0 || h == null || h <= 0)) {
      final vb = _extractAttr(tag, 'viewBox');
      if (vb != null) {
        final parts = vb.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 4) {
          final vw = double.tryParse(parts[2]);
          final vh = double.tryParse(parts[3]);
          if (vw != null && vw > 0 && vh != null && vh > 0) {
            w = w ?? vw;
            h = h ?? vh;
          }
        }
      }
    }
    if (w == null || w <= 0 || h == null || h <= 0) return null;
    return ImageDimensions(w.toInt(), h.toInt());
  }

  static String? _extractAttr(String tag, String name) {
    final m = RegExp('$name="([^"]*)"').firstMatch(tag);
    if (m != null) return m.group(1);
    final m2 = RegExp("$name='([^']*)'").firstMatch(tag);
    return m2?.group(1);
  }

  static double? _parseSvgLength(String? s) {
    if (s == null || s.isEmpty) return null;
    // 去除单位（px/pt/in/mm/cm/% 等）
    final m = RegExp(r'^([\d.]+)').firstMatch(s.trim());
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
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

  Future<Meme> importText(String text, {String? name, String? folderId, List<String> tags = const [], String type = Meme.typeText}) async {
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
      type: type,
      textContent: text,
    );
    await _saveMeme(meme, null);
    return meme;
  }

  /// 自然排序比较器：page_1.jpg < page_2.jpg < page_10.jpg
  int _naturalCompare(String a, String b) {
    final ra = RegExp(r'(\d+|\D+)').allMatches(a).map((m) => m.group(0)!).toList();
    final rb = RegExp(r'(\d+|\D+)').allMatches(b).map((m) => m.group(0)!).toList();
    for (var i = 0; i < ra.length && i < rb.length; i++) {
      final x = ra[i], y = rb[i];
      final xIsDigit = RegExp(r'^\d+$').hasMatch(x);
      final yIsDigit = RegExp(r'^\d+$').hasMatch(y);
      if (xIsDigit && yIsDigit) {
        final xn = int.parse(x), yn = int.parse(y);
        if (xn != yn) return xn.compareTo(yn);
      } else {
        final cmp = x.toLowerCase().compareTo(y.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }
    return ra.length.compareTo(rb.length);
  }

  /// 导入漫画：手动多图合并
  /// [files] 已按顺序排好（首页在前），将每个文件存入存储，第一页作为封面
  Future<Meme> importMangaFromFiles(List<PlatformFile> files, {String? name, String? folderId}) async {
    if (files.isEmpty) {
      throw ArgumentError('files is empty');
    }
    final id = _uuid.v4();
    final now = DateTime.now();
    final pagePaths = <String>[];
    int totalSize = 0;

    for (final file in files) {
      final pageId = _uuid.v4();
      final ext = _guessExt(file.name);
      final fileName = '${pageId}_page${pagePaths.length + 1}$ext';
      final relPath = 'memes/$fileName';

      if (kIsWeb) {
        if (file.bytes != null) {
          await webStorageSetBinary(relPath, file.bytes!);
          totalSize += file.bytes!.length;
        }
      } else {
        final dest = File(p.join(_basePath!, relPath));
        await dest.create(recursive: true);
        if (file.path != null) {
          await File(file.path!).copy(dest.path);
          totalSize += await dest.length();
        } else if (file.bytes != null) {
          await dest.writeAsBytes(file.bytes!);
          totalSize += file.bytes!.length;
        }
      }
      pagePaths.add(relPath);
    }

    final meme = Meme(
      id: id,
      name: name ?? p.basenameWithoutExtension(files.first.name),
      filePath: pagePaths.first,
      folderId: folderId,
      tags: const [],
      createdAt: now,
      mimeType: 'image/zip',
      fileSize: totalSize,
      type: Meme.typeManga,
      pages: pagePaths,
    );
    await _saveMeme(meme, null);
    return meme;
  }

  /// 导入漫画：从 CBZ/ZIP 压缩包解压图片
  /// 按文件名自然排序后作为页面顺序
  Future<Meme> importMangaFromArchive(PlatformFile file, {String? name, String? folderId}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final imageExts = <String>{'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.apng'};
    final pagePaths = <String>[];
    int totalSize = 0;

    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null) throw ArgumentError('web archive bytes is null');
      final archive = ZipDecoder().decodeBytes(bytes);
      final entries = archive.files.where((e) => e.isFile).toList()
        ..sort((a, b) => _naturalCompare(a.name, b.name));
      for (final entry in entries) {
        final ext = p.extension(entry.name).toLowerCase();
        if (!imageExts.contains(ext)) continue;
        final pageId = _uuid.v4();
        final relPath = 'memes/${pageId}_page${pagePaths.length + 1}$ext';
        final data = entry.content as List<int>;
        final ub = data is Uint8List ? data : Uint8List.fromList(data);
        await webStorageSetBinary(relPath, ub);
        totalSize += ub.length;
        pagePaths.add(relPath);
      }
    } else {
      if (file.path == null) throw ArgumentError('archive path is null');
      final inputStream = InputFileStream(file.path!);
      final archive = ZipDecoder().decodeStream(inputStream);
      final entries = archive.files.where((e) => e.isFile).toList()
        ..sort((a, b) => _naturalCompare(a.name, b.name));
      for (final entry in entries) {
        final ext = p.extension(entry.name).toLowerCase();
        if (!imageExts.contains(ext)) continue;
        final pageId = _uuid.v4();
        final relPath = 'memes/${pageId}_page${pagePaths.length + 1}$ext';
        final dest = File(p.join(_basePath!, relPath));
        await dest.create(recursive: true);
        final data = entry.content as List<int>;
        await dest.writeAsBytes(data);
        totalSize += data.length;
        pagePaths.add(relPath);
      }
      inputStream.close();
    }

    if (pagePaths.isEmpty) {
      throw StateError('archive contains no images');
    }

    final meme = Meme(
      id: id,
      name: name ?? p.basenameWithoutExtension(file.name),
      filePath: pagePaths.first,
      folderId: folderId,
      tags: const [],
      createdAt: now,
      mimeType: 'image/zip',
      fileSize: totalSize,
      type: Meme.typeManga,
      pages: pagePaths,
    );
    await _saveMeme(meme, null);
    return meme;
  }

  /// 导入立绘/CG：多图合并为精灵图层
  /// [files] 第一个为基础层，其余按差分处理（可手动标记类别）
  /// [type] 必须为 typePortrait 或 typeCg
  /// [categories] 可选，每层对应的 SpriteCategory（长度需与 files 一致）
  Future<Meme> importSpriteFromFiles(
    List<PlatformFile> files, {
    String? name,
    String? folderId,
    required String type,
    List<String>? categories,
  }) async {
    if (files.isEmpty) {
      throw ArgumentError('files is empty');
    }
    if (type != Meme.typePortrait && type != Meme.typeCg) {
      throw ArgumentError('type must be portrait or cg');
    }

    final id = _uuid.v4();
    final now = DateTime.now();
    final spriteLayers = <Map<String, dynamic>>[];
    final layerBytesList = <Uint8List>[];
    final zOrders = <int>[];
    int totalSize = 0;
    int imgWidth = 0;
    int imgHeight = 0;

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final layerId = _uuid.v4();
      final ext = _guessExt(file.name);
      final fileName = '${layerId}_layer$i$ext';
      final relPath = 'memes/$fileName';

      Uint8List? bytes;
      if (kIsWeb) {
        if (file.bytes != null) {
          await webStorageSetBinary(relPath, file.bytes!);
          bytes = file.bytes!;
          totalSize += bytes.length;
        }
      } else {
        final dest = File(p.join(_basePath!, relPath));
        await dest.create(recursive: true);
        if (file.path != null) {
          await File(file.path!).copy(dest.path);
          totalSize += await dest.length();
          bytes = await dest.readAsBytes();
        } else if (file.bytes != null) {
          await dest.writeAsBytes(file.bytes!);
          bytes = file.bytes!;
          totalSize += bytes.length;
        }
      }

      // 推断类别
      final layerName = p.basenameWithoutExtension(file.name);
      String category;
      if (categories != null && i < categories.length) {
        category = categories[i];
      } else {
        category = i == 0 ? SpriteCategory.base : SpriteCategory.guess(layerName);
      }

      spriteLayers.add({
        'name': layerName,
        'path': relPath,
        'category': category,
        'visible': i == 0, // 默认只显示基础层
        'zOrder': i,
      });

      if (bytes != null) {
        layerBytesList.add(bytes);
        zOrders.add(i);
        // 从第一层提取宽高
        if (i == 0 && bytes.isNotEmpty) {
          final dims = parseImageDimensionsFromHeader(bytes);
          if (dims != null) {
            imgWidth = dims.width;
            imgHeight = dims.height;
          }
        }
      }
    }

    // 生成合成预览 PNG（基础层 + 所有默认 visible 的层）
    String? thumbPath;
    if (layerBytesList.isNotEmpty) {
      final visibleBytes = <Uint8List>[];
      final visibleZOrders = <int>[];
      for (var i = 0; i < spriteLayers.length; i++) {
        if (spriteLayers[i]['visible'] == true && i < layerBytesList.length) {
          visibleBytes.add(layerBytesList[i]);
          visibleZOrders.add(spriteLayers[i]['zOrder'] as int);
        }
      }
      final previewPng = SpriteService.composePreview(visibleBytes, visibleZOrders);
      if (previewPng != null) {
        thumbPath = await _saveThumbPng(id, previewPng);
      }
    }

    final meme = Meme(
      id: id,
      name: name ?? p.basenameWithoutExtension(files.first.name),
      filePath: spriteLayers.isNotEmpty ? spriteLayers.first['path'] as String : '',
      folderId: folderId,
      tags: const [],
      createdAt: now,
      mimeType: 'image/png',
      fileSize: totalSize,
      type: type,
      thumbPath: thumbPath,
      spriteLayers: spriteLayers,
      width: imgWidth,
      height: imgHeight,
    );
    await _saveMeme(meme, null);
    return meme;
  }

  /// 导入立绘/CG：从 krkr pjson 文件 + 同目录图片
  /// [pjsonFile] pjson 描述文件
  /// [imageFiles] pjson 引用的图片文件列表
  Future<Meme> importSpriteFromPjson(
    PlatformFile pjsonFile,
    List<PlatformFile> imageFiles, {
    String? name,
    String? folderId,
    required String type,
  }) async {
    if (type != Meme.typePortrait && type != Meme.typeCg) {
      throw ArgumentError('type must be portrait or cg');
    }

    // 读取 pjson 内容
    String? jsonStr;
    if (pjsonFile.bytes != null) {
      jsonStr = utf8.decode(pjsonFile.bytes!);
    } else if (pjsonFile.path != null && !kIsWeb) {
      jsonStr = await File(pjsonFile.path!).readAsString();
    }
    if (jsonStr == null) throw ArgumentError('cannot read pjson content');

    final result = SpriteService.parsePjson(jsonStr);
    if (result == null || result.layers.isEmpty) {
      throw ArgumentError('invalid pjson format');
    }

    // 构建 imageFiles 的查找索引（按文件名匹配）
    final imageMap = <String, PlatformFile>{};
    for (final f in imageFiles) {
      imageMap[p.basename(f.name)] = f;
      // 同时存不带路径的文件名
      final baseName = p.basenameWithoutExtension(f.name);
      imageMap[baseName] = f;
    }

    final id = _uuid.v4();
    final now = DateTime.now();
    final spriteLayers = <Map<String, dynamic>>[];
    int totalSize = 0;
    int matchedCount = 0;

    for (final layer in result.layers) {
      final imageFile = layer['imageFile'] as String;
      // 尝试多种匹配：完整路径 / basename / basenameWithoutExt
      PlatformFile? matched;
      final candidates = [
        imageFile,
        p.basename(imageFile),
        p.basenameWithoutExtension(imageFile),
      ];
      for (final c in candidates) {
        if (imageMap.containsKey(c)) {
          matched = imageMap[c];
          break;
        }
      }
      if (matched == null) continue; // 跳过未匹配的图层

      final layerId = _uuid.v4();
      final ext = _guessExt(matched.name);
      final fileName = '${layerId}_layer$matchedCount$ext';
      final relPath = 'memes/$fileName';

      Uint8List? bytes;
      if (kIsWeb) {
        if (matched.bytes != null) {
          await webStorageSetBinary(relPath, matched.bytes!);
          bytes = matched.bytes!;
          totalSize += bytes.length;
        }
      } else {
        final dest = File(p.join(_basePath!, relPath));
        await dest.create(recursive: true);
        if (matched.path != null) {
          await File(matched.path!).copy(dest.path);
          totalSize += await dest.length();
          bytes = await dest.readAsBytes();
        } else if (matched.bytes != null) {
          await dest.writeAsBytes(matched.bytes!);
          bytes = matched.bytes!;
          totalSize += bytes.length;
        }
      }

      final layerName = layer['name'] as String? ?? p.basenameWithoutExtension(matched.name);
      final category = layer['category'] as String? ?? SpriteCategory.expression;

      spriteLayers.add({
        'name': layerName,
        'path': relPath,
        'category': category,
        'visible': matchedCount == 0 || category == SpriteCategory.base,
        'zOrder': layer['zOrder'] as int? ?? matchedCount,
      });
      matchedCount++;
    }

    if (spriteLayers.isEmpty) {
      throw ArgumentError('no matched images found in pjson');
    }

    // 生成合成预览
    String? thumbPath;
    final previewBytes = <Uint8List>[];
    final previewZOrders = <int>[];
    for (final sl in spriteLayers) {
      if (sl['visible'] == true) {
        final relPath = sl['path'] as String;
        Uint8List? lb;
        if (kIsWeb) {
          lb = await readMemeBytes(relPath);
        } else {
          final f = File(p.join(_basePath!, relPath));
          if (await f.exists()) lb = await f.readAsBytes();
        }
        if (lb != null) {
          previewBytes.add(lb);
          previewZOrders.add(sl['zOrder'] as int);
        }
      }
    }
    if (previewBytes.isNotEmpty) {
      final previewPng = SpriteService.composePreview(previewBytes, previewZOrders);
      if (previewPng != null) {
        thumbPath = await _saveThumbPng(id, previewPng);
      }
    }

    final meme = Meme(
      id: id,
      name: name ?? result.name ?? p.basenameWithoutExtension(pjsonFile.name),
      filePath: spriteLayers.first['path'] as String,
      folderId: folderId,
      tags: const [],
      createdAt: now,
      mimeType: 'image/png',
      fileSize: totalSize,
      type: type,
      thumbPath: thumbPath,
      spriteLayers: spriteLayers,
      width: result.width,
      height: result.height,
    );
    await _saveMeme(meme, null);
    return meme;
  }

  Future<void> deleteMeme(String id) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;

    // 删除主文件
    if (!kIsWeb && meme.filePath.isNotEmpty) {
      final file = File(p.join(_basePath!, meme.filePath));
      if (await file.exists()) await file.delete();
    }
    if (kIsWeb && meme.filePath.isNotEmpty) {
      await webStorageDelete(meme.filePath);
    }

    // 漫画：删除所有页面（filePath 已包含在 pages 中，但遍历以保险）
    if (meme.isManga) {
      for (final page in meme.pages) {
        if (page == meme.filePath) continue;
        if (!kIsWeb) {
          final f = File(p.join(_basePath!, page));
          if (await f.exists()) await f.delete();
        } else {
          await webStorageDelete(page);
        }
      }
    }

    // 立绘/CG：删除所有图层文件
    if (meme.spriteLayers != null) {
      for (final layer in meme.spriteLayers!) {
        final layerPath = layer['path'] as String?;
        if (layerPath == null || layerPath == meme.filePath) continue;
        if (!kIsWeb) {
          final f = File(p.join(_basePath!, layerPath));
          if (await f.exists()) await f.delete();
        } else {
          await webStorageDelete(layerPath);
        }
      }
    }

    // 删除缩略图
    if (meme.thumbPath != null && meme.thumbPath!.isNotEmpty) {
      if (!kIsWeb) {
        final f = File(p.join(_basePath!, meme.thumbPath!));
        if (await f.exists()) await f.delete();
      } else {
        await webStorageDelete(meme.thumbPath!);
      }
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

  /// 更新文本/小说内容（可选更新标题）
  Future<void> updateMemeText(String id, String text, {String? name}) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    final updated = meme.copyWith(
      textContent: text,
      fileSize: text.length,
      name: name ?? meme.name,
    );
    await _memeBox!.put(id, updated.toMap());
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

  Future<void> addTagToMeme(String id, String tag) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    if (meme.tags.contains(tag)) return;
    await _memeBox!.put(id, meme.copyWith(tags: [...meme.tags, tag]).toMap());
  }

  Future<void> removeTagFromMeme(String id, String tag) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    if (!meme.tags.contains(tag)) return;
    await _memeBox!.put(
      id,
      meme.copyWith(tags: meme.tags.where((t) => t != tag).toList()).toMap(),
    );
  }

  // ======================== Mood CRUD ========================

  /// 添加情绪标签（带权重 1-5）
  Future<void> addMoodToMeme(String id, String mood, int weight) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    final w = weight.clamp(1, 5);
    // 已存在则更新权重
    final moods = List<Map<String, dynamic>>.from(meme.moods);
    final idx = moods.indexWhere((m) => m['name'] == mood);
    if (idx >= 0) {
      moods[idx] = {'name': mood, 'weight': w};
    } else {
      moods.add({'name': mood, 'weight': w});
    }
    await _memeBox!.put(id, meme.copyWith(moods: moods).toMap());
  }

  /// 移除情绪标签
  Future<void> removeMoodFromMeme(String id, String mood) async {
    if (_memeBox == null) return;
    final meme = _getMeme(id);
    if (meme == null) return;
    final moods = meme.moods.where((m) => m['name'] != mood).toList();
    await _memeBox!.put(id, meme.copyWith(moods: moods).toMap());
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
      case '.apng': return 'image/apng';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      case '.bmp': return 'image/bmp';
      case '.svg': return 'image/svg+xml';
      case '.psd': return 'image/vnd.adobe.photoshop';
      case '.ico': return 'image/x-icon';
      case '.tif': case '.tiff': return 'image/tiff';
      case '.pdf': return 'application/pdf';
      default: return 'image/png';
    }
  }

  String _guessExt(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return '.png';
    return fileName.substring(dot).toLowerCase();
  }

  String _guessType(String ext) {
    switch (ext) {
      case '.gif': return Meme.typeGif;
      case '.apng': return Meme.typeGif; // APNG 当动图处理
      case '.svg': return Meme.typeVector;
      case '.psd': return Meme.typePsd;
      case '.pdf': return Meme.typePdf;
      default: return Meme.typeImage; // ico/tif/bmp/png/jpg/webp 均为普通图片
    }
  }
}
