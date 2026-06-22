import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// 表情包文件存储服务
/// - Native: 文件存储在本地磁盘
/// - Web:   文件以字节形式存储在内存 Map 中（页面刷新后丢失）
class FileService {
  static const _stickerDir = 'stickers';
  final Uuid _uuid = const Uuid();

  // Web 端的内存缓存: storedFilename → bytes
  static final Map<String, Uint8List> _webCache = {};

  // ==================== 导入 ====================

  /// 导入文件，返回存储后的文件名
  /// Native: 复制到应用目录
  /// Web:    存入内存缓存
  Future<String> importFile(String sourcePath, {Uint8List? bytes}) async {
    final ext = p.extension(sourcePath);
    final newName = '${_uuid.v4()}$ext';

    if (kIsWeb) {
      if (bytes != null) {
        _webCache[newName] = bytes;
      }
      return newName;
    }

    // Native: 复制到本地
    final root = await stickerRootDir;
    final destFile = File(p.join(root.path, newName));
    await File(sourcePath).copy(destFile.path);
    return newName;
  }

  /// 批量导入
  Future<List<String>> importFiles(List<String> sourcePaths,
      {List<Uint8List?>? bytesList}) async {
    final results = <String>[];
    for (var i = 0; i < sourcePaths.length; i++) {
      try {
        final result = await importFile(
          sourcePaths[i],
          bytes: bytesList != null && i < bytesList.length ? bytesList[i] : null,
        );
        results.add(result);
      } catch (_) {}
    }
    return results;
  }

  // ==================== 读取 ====================

  /// 获取文件的完整路径（Native）或占位符（Web）
  Future<String> fullPath(String storedFilename) async {
    if (kIsWeb) {
      return storedFilename; // 仅作为标识符
    }
    final root = await stickerRootDir;
    return p.join(root.path, storedFilename);
  }

  /// 获取文件的字节数据 (双平台)
  Future<Uint8List?> readBytes(String storedFilename) async {
    if (kIsWeb) {
      return _webCache[storedFilename];
    }
    final fp = await fullPath(storedFilename);
    final file = File(fp);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  // ==================== 删除 ====================

  /// 删除存储的文件
  Future<void> deleteFile(String storedFilename) async {
    if (kIsWeb) {
      _webCache.remove(storedFilename);
      return;
    }
    final root = await stickerRootDir;
    final file = File(p.join(root.path, storedFilename));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ==================== 图片尺寸 ====================

  /// 读取图片尺寸
  Future<(int, int)?> getImageDimensions(String storedFilename) async {
    final bytes = await readBytes(storedFilename);
    if (bytes == null) return null;
    return _dimensionsFromBytes(bytes);
  }

  (int, int)? _dimensionsFromBytes(List<int> bytes) {
    if (bytes.length < 24) return null;
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) {
      return (256, 256);
    }
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      final w = bytes[6] | (bytes[7] << 8);
      final h = bytes[8] | (bytes[9] << 8);
      return (w, h);
    }
    // WebP
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return (256, 256);
    }
    return null;
  }

  // ==================== 本地目录 (Native only) ====================

  Future<Directory> get stickerRootDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _stickerDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
