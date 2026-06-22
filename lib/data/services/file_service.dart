import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';

/// 管理表情包图片文件的本地存储
class FileService {
  static const _stickerDir = 'stickers';
  final Uuid _uuid = const Uuid();

  /// 获取应用内表情包文件的根目录
  Future<Directory> get stickerRootDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _stickerDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 将外部文件复制到应用内部存储，返回新路径
  /// 返回相对路径（相对于 stickerRootDir）
  Future<String> importFile(String sourcePath) async {
    final root = await stickerRootDir;
    final ext = p.extension(sourcePath);
    final newName = '${_uuid.v4()}$ext';
    final destFile = File(p.join(root.path, newName));
    await File(sourcePath).copy(destFile.path);
    return newName; // 只存文件名，方便跨平台
  }

  /// 构建 sticker 文件的完整路径
  Future<String> fullPath(String storedFilename) async {
    final root = await stickerRootDir;
    return p.join(root.path, storedFilename);
  }

  /// 删除 sticker 文件
  Future<void> deleteFile(String storedFilename) async {
    final root = await stickerRootDir;
    final file = File(p.join(root.path, storedFilename));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 读取图片尺寸（通过读取文件头部字节）
  /// 返回 (width, height)
  Future<(int, int)?> getImageDimensions(String storedFilename) async {
    final fp = await fullPath(storedFilename);
    final file = File(fp);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final mimeType = lookupMimeType(fp, headerBytes: bytes);

    if (mimeType == 'image/png') {
      return _readPngSize(bytes);
    } else if (mimeType == 'image/gif') {
      return _readGifSize(bytes);
    } else if (mimeType == 'image/webp') {
      return _readWebpSize(bytes);
    }
    return null;
  }

  /// PNG: IHDR chunk 从 offset 16 开始，前8字节 = width(4) height(4)
  (int, int)? _readPngSize(List<int> bytes) {
    if (bytes.length < 24) return null;
    final w = _readInt32(bytes, 16);
    final h = _readInt32(bytes, 20);
    return (w, h);
  }

  /// GIF: offset 6 = width(2) height(2) little-endian
  (int, int)? _readGifSize(List<int> bytes) {
    if (bytes.length < 10) return null;
    final w = bytes[6] | (bytes[7] << 8);
    final h = bytes[8] | (bytes[9] << 8);
    return (w, h);
  }

  /// WebP: 需检查 VP8 / VP8L / VP8X 格式
  (int, int)? _readWebpSize(List<int> bytes) {
    if (bytes.length < 30) return null;
    // VP8 (lossy): bytes[26]=w(2) bytes[26+2]=h(2)
    // VP8L: bytes[25]=w(2) bytes[27]=h including some flags
    // VP8X: bytes[24]=w(3) bytes[27]=h(3)
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    if (chunk == 'VP8 ' && bytes.length >= 30) {
      final w = bytes[26] | (bytes[27] << 8);
      final h = bytes[28] | (bytes[29] << 8);
      return (w, h);
    } else if (chunk == 'VP8L' && bytes.length >= 30) {
      final w = 1 + ((bytes[22] & 0x3F) << 8) | bytes[21];
      final h = 1 +
          (((bytes[24] & 0xF) << 10) |
              (bytes[23] << 2) |
              ((bytes[22] & 0xC0) >> 6));
      return (w, h);
    } else if (chunk == 'VP8X' && bytes.length >= 30) {
      final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
      return (w, h);
    }
    return null;
  }

  int _readInt32(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
