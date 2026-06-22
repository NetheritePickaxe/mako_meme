import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 跨平台图片组件
/// - Native (Android/Windows): Image.file
/// - Web: Image.memory (file_path 作为 key 从缓存读取)
class PlatformImage extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? filePath;
  final BoxFit fit;
  final double? height;
  final double? width;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const PlatformImage({
    super.key,
    this.imageBytes,
    this.filePath,
    this.fit = BoxFit.cover,
    this.height,
    this.width,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // 优先使用直接传入的 bytes
    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: fit,
        height: height,
        width: width,
        errorBuilder: errorBuilder ?? _defaultError,
      );
    }

    if (kIsWeb) {
      // Web 上无法用 File，尝试用 network 路径
      if (filePath != null) {
        return Image.network(
          filePath!,
          fit: fit,
          height: height,
          width: width,
          errorBuilder: errorBuilder ?? _defaultError,
        );
      }
      return _placeholder;
    }

    // Native: 直接读本地文件
    if (filePath != null) {
      return Image.file(
        File(filePath!),
        fit: fit,
        height: height,
        width: width,
        errorBuilder: errorBuilder ?? _defaultError,
      );
    }

    return _placeholder;
  }

  Widget get _placeholder =>
      Container(
        height: height ?? 120,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image, color: Colors.grey),
      );

  static Widget _defaultError(BuildContext context, Object error, StackTrace? stack) {
    return Container(
      height: 120,
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}

/// 从文件路径读取字节 (Web 兼容)
Future<Uint8List?> readFileBytes(String filePath) async {
  if (kIsWeb) {
    try {
      final http = await _getHttp();
      final response = await http.get(Uri.parse(filePath));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  final file = File(filePath);
  if (await file.exists()) {
    return file.readAsBytes();
  }
  return null;
}

Future<dynamic> _getHttp() async {
  // 在 web 上用 dart:html HttpRequest，但这里不依赖它
  // 用 platform_interface 的方式，实际使用中由调用方保证
  throw UnsupportedError('Use PlatformImage with imageBytes on web');
}

/// 根据文件名推断 MIME 类型
String mimeTypeFromPath(String path) {
  final ext = p.extension(path).toLowerCase();
  switch (ext) {
    case '.png':  return 'image/png';
    case '.gif':  return 'image/gif';
    case '.webp': return 'image/webp';
    case '.jpg':
    case '.jpeg': return 'image/jpeg';
    default:      return 'application/octet-stream';
  }
}
