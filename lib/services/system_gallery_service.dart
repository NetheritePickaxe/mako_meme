import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/meme.dart';

/// 系统图集服务：管理绑定的系统目录，扫描图片并构建虚拟 Meme 对象。
///
/// 系统图集是只读的特殊分类，不存入数据库。虚拟 Meme 的 id 以 'sysgal://' 前缀
/// 标识，filePath 为绝对路径（系统目录中的真实文件路径）。
class SystemGalleryService {
  /// 支持的图片扩展名（小写，含点）
  static const Set<String> imageExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg', '.apng',
  };

  /// 调起系统目录选择器（SAF / 文件夹选择器），返回选中目录的文件系统路径。
  ///
  /// Android 上 file_picker 返回 content:// URI（如
  /// content://com.android.externalstorage.documents/tree/primary%3ADCIM%2FCamera），
  /// 需要解析转换为文件系统路径（/storage/emulated/0/DCIM/Camera）才能用 File API 读取。
  /// 仅支持 primary:（内置存储）和 XXXX-XXXX:（SD 卡）格式的 URI。
  /// 用户取消或转换失败返回 null。
  static Future<String?> pickDirectory() async {
    String? picked;
    try {
      picked = await FilePicker.platform.getDirectoryPath();
    } catch (e) {
      debugPrint('[SystemGallery] pickDirectory failed: $e');
      return null;
    }
    if (picked == null || picked.isEmpty) return null;
    return _resolvePath(picked);
  }

  /// 把 file_picker 返回的字符串解析为文件系统路径。
  /// - 普通 filesystem path（Windows / 已转换的 Android）：直接返回
  /// - content:// URI（Android SAF）：解析 tree 段并转换为 /storage/... 路径
  /// 转换失败返回 null。
  static String? _resolvePath(String raw) {
    // Windows 或已转换的路径：直接返回
    if (!raw.startsWith('content://')) return raw;

    // Android SAF URI：content://com.android.externalstorage.documents/tree/primary%3ADCIM%2FCamera
    try {
      final uri = Uri.parse(raw);
      // path 段：/tree/primary:DCIM/Camera
      final pathSegments = uri.pathSegments;
      // 寻找 'tree' 后的部分
      final treeIdx = pathSegments.indexOf('tree');
      if (treeIdx < 0 || treeIdx + 1 >= pathSegments.length) return null;
      // 注意：Uri.pathSegments 会按 / 切分，但 primary:DCIM/Camera 中的 / 也会被切，
      // 需要重新拼接
      final afterTree = pathSegments.sublist(treeIdx + 1).join('/');
      // URL 解码（如 %3A → :，%2F → /）
      final decoded = Uri.decodeComponent(afterTree);
      // decoded 形如 "primary:DCIM/Camera" 或 "1234-5678:DCIM"
      final colonIdx = decoded.indexOf(':');
      if (colonIdx <= 0) return null;
      final volumeLabel = decoded.substring(0, colonIdx);
      final relativePath = decoded.substring(colonIdx + 1);
      // primary → /storage/emulated/0/
      // 其他（如 1234-5678）→ /storage/1234-5678/
      final storageRoot = volumeLabel == 'primary'
          ? '/storage/emulated/0'
          : '/storage/$volumeLabel';
      final fsPath = relativePath.isEmpty
          ? storageRoot
          : '$storageRoot/$relativePath';
      return fsPath;
    } catch (e) {
      debugPrint('[SystemGallery] _resolvePath failed: $e (raw=$raw)');
      return null;
    }
  }

  /// 扫描目录下的图片文件（不递归子目录），返回绝对路径列表。
  /// 目录不存在或无权限返回空列表。
  static Future<List<String>> listImages(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];
      final results = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (imageExtensions.contains(ext)) {
            results.add(entity.path);
          }
        }
      }
      results.sort();
      return results;
    } catch (e) {
      debugPrint('[SystemGallery] listImages failed for $dirPath: $e');
      return [];
    }
  }

  /// 把绝对路径的图片文件包装为虚拟 Meme 对象。
  /// id 用 'sysgal://' 前缀 + 绝对路径，确保唯一且可识别。
  /// type 根据扩展名推断（image/gif/vector），保留渲染逻辑。
  static Future<Meme> buildVirtualMeme(String absPath) async {
    final basename = p.basenameWithoutExtension(absPath);
    final ext = p.extension(absPath).toLowerCase();
    final mime = _guessMime(ext);
    final type = _guessType(ext);

    int fileSize = 0;
    DateTime modified = DateTime.now();
    try {
      final stat = await FileStat.stat(absPath);
      fileSize = stat.size;
      modified = stat.modified;
    } catch (_) {}

    return Meme(
      id: 'sysgal://$absPath',
      name: basename,
      filePath: absPath,
      folderId: null,
      tags: const [],
      createdAt: modified,
      mimeType: mime,
      fileSize: fileSize,
      type: type,
    );
  }

  static String _guessMime(String ext) {
    switch (ext) {
      case '.png': return 'image/png';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      case '.bmp': return 'image/bmp';
      case '.svg': return 'image/svg+xml';
      case '.apng': return 'image/apng';
      default: return '';
    }
  }

  static String _guessType(String ext) {
    switch (ext) {
      case '.gif':
      case '.apng':
        return Meme.typeGif;
      case '.svg':
        return Meme.typeVector;
      default:
        return Meme.typeImage;
    }
  }
}
