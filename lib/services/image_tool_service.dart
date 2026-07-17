import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../models/meme.dart';
import 'storage_platform.dart';
import 'storage_service.dart';

/// 图片处理服务：基于纯 Dart `image` 包，全平台通用。
///
/// 功能：
/// 1. 格式转换：JPG / PNG / WebP / BMP / GIF 互转
/// 2. 尺寸修改：按宽高 / 百分比缩放，支持保持比例
/// 3. 多图转 GIF / APNG：将多张图片按顺序合并为动图
class ImageToolService {
  final StorageService _storage;
  ImageToolService(this._storage);

  /// 支持的输出格式（image 包 4.x 未导出 WebP 编码器，故不支持输出 WebP）
  static const outputFormats = ['png', 'jpg', 'bmp', 'gif'];

  /// 读取图片为 [img.Image]（解码）
  /// 优先用 bytes（web），其次用 File（原生）
  Future<img.Image?> decode(String filePath) async {
    final bytes = await _storage.readMemeBytes(filePath);
    if (bytes == null) {
      final f = _storage.getMemeFile(filePath);
      if (f != null && await f.exists()) {
        return img.decodeImage(await f.readAsBytes());
      }
      return null;
    }
    return img.decodeImage(bytes);
  }

  /// 编码为指定格式
  Uint8List encode(img.Image image, String format, {int quality = 90}) {
    switch (format.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return img.encodeJpg(image, quality: quality);
      case 'bmp':
        return img.encodeBmp(image);
      case 'gif':
        return img.encodeGif(image);
      case 'png':
      default:
        return img.encodePng(image);
    }
  }

  /// 转换格式并保存为新的 meme
  /// [srcPath] 源文件相对路径；[format] 目标格式（如 'png'）
  /// 返回新生成的 Meme
  Future<Meme> convertFormat(String srcPath, String format, {int quality = 90, String? name, String? folderId}) async {
    final image = await decode(srcPath);
    if (image == null) throw StateError('decode failed: $srcPath');
    final bytes = encode(image, format, quality: quality);
    final newExt = '.${format.toLowerCase()}';
    return _saveAndCreateMeme(bytes, newExt,
      name: name ?? p.basenameWithoutExtension(srcPath),
      format: format.toLowerCase(),
      folderId: folderId,
    );
  }

  /// 修改尺寸并保存为新的 meme
  /// [width]/[height] 为目标尺寸，设为 null 表示按另一边等比缩放
  /// [percent] 不为 null 时按百分比缩放（0.0~1.0）
  Future<Meme> resize(
    String srcPath, {
    int? width,
    int? height,
    double? percent,
    String? name,
    String? folderId,
  }) async {
    final image = await decode(srcPath);
    if (image == null) throw StateError('decode failed: $srcPath');
    final srcW = image.width;
    final srcH = image.height;

    int targetW;
    int targetH;
    if (percent != null) {
      targetW = (srcW * percent).round();
      targetH = (srcH * percent).round();
    } else if (width != null && height != null) {
      targetW = width;
      targetH = height;
    } else if (width != null) {
      targetW = width;
      targetH = (srcH * width / srcW).round();
    } else if (height != null) {
      targetH = height;
      targetW = (srcW * height / srcH).round();
    } else {
      throw ArgumentError('at least one of width/height/percent required');
    }
    if (targetW < 1) targetW = 1;
    if (targetH < 1) targetH = 1;

    final resized = img.copyResize(image, width: targetW, height: targetH);
    final ext = p.extension(srcPath).toLowerCase();
    final formatStr = ext.isEmpty ? 'png' : ext.substring(1);
    final bytes = encode(resized, formatStr);
    return _saveAndCreateMeme(bytes, ext.isEmpty ? '.png' : ext,
      name: name ?? p.basenameWithoutExtension(srcPath),
      format: formatStr,
      folderId: folderId,
    );
  }

  /// 多图转 GIF
  /// [srcPaths] 源图片相对路径列表；[frameDurationMs] 每帧时长（毫秒）
  Future<Meme> imagesToGif(List<String> srcPaths, {int frameDurationMs = 200, String? name, String? folderId}) async {
    final bytes = await _buildAnimation(srcPaths, frameDurationMs, (image) => img.encodeGif(image));
    return _saveAndCreateMeme(bytes, '.gif',
      name: name ?? 'animation',
      format: 'gif',
      folderId: folderId,
      isAnimated: true,
    );
  }

  /// 多图转 APNG
  /// [srcPaths] 源图片相对路径列表；[frameDurationMs] 每帧时长（毫秒）
  Future<Meme> imagesToApng(List<String> srcPaths, {int frameDurationMs = 200, String? name, String? folderId}) async {
    final bytes = await _buildAnimation(srcPaths, frameDurationMs, (image) => img.encodePng(image));
    return _saveAndCreateMeme(bytes, '.apng',
      name: name ?? 'animation',
      format: 'apng',
      folderId: folderId,
      isAnimated: true,
    );
  }

  /// 幻影坦克图制作
  /// 前景图在黑底显示，背景图在白底显示，合成一张带透明通道的 PNG。
  /// [fgPath] 前景图（黑底显示）；[bgPath] 背景图（白底显示）
  /// [colorMode] true=彩色输出（保留前景色彩），false=黑白输出
  /// [brightnessRatio] 亮度比例 (0.5~2.0)，整体缩放前后景亮度
  /// [colorIntensity] 色彩强度 (0.0~1.0)，仅彩色模式有效，控制前景饱和度
  Future<Meme> makePhantomTank(
    String fgPath,
    String bgPath, {
    bool colorMode = true,
    double brightnessRatio = 1.0,
    double colorIntensity = 1.0,
    String? name,
    String? folderId,
  }) async {
    final fg = await decode(fgPath);
    final bg = await decode(bgPath);
    if (fg == null || bg == null) throw StateError('decode failed');
    // 统一尺寸：以前景为基准，背景缩放对齐
    final w = fg.width;
    final h = fg.height;
    final bgResized = (bg.width == w && bg.height == h)
        ? bg
        : img.copyResize(bg, width: w, height: h);

    final out = img.Image(width: w, height: h, numChannels: 4);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final fp = fg.getPixel(x, y);
        final bp = bgResized.getPixel(x, y);
        // 亮度（0-255）
        double ga = 0.299 * fp.r + 0.587 * fp.g + 0.114 * fp.b;
        double gb = 0.299 * bp.r + 0.587 * bp.g + 0.114 * bp.b;
        // 亮度比例
        ga = (ga * brightnessRatio).clamp(0.0, 255.0);
        gb = (gb * brightnessRatio).clamp(0.0, 255.0);
        // alpha = 255 - gb + ga（黑底显示前景、白底显示背景）
        int alpha = (255 - gb + ga).round().clamp(0, 255);

        if (colorMode) {
          // 彩色：保留前景色彩
          double ar = fp.r.toDouble();
          double ag = fp.g.toDouble();
          double ab = fp.b.toDouble();
          // 色彩强度：向灰度混合（1.0=全彩，0.0=纯灰）
          if (colorIntensity < 1.0) {
            ar = ga + (ar - ga) * colorIntensity;
            ag = ga + (ag - ga) * colorIntensity;
            ab = ga + (ab - ga) * colorIntensity;
          }
          int r, g, b;
          if (alpha > 0) {
            r = (ar * 255 / alpha).round().clamp(0, 255);
            g = (ag * 255 / alpha).round().clamp(0, 255);
            b = (ab * 255 / alpha).round().clamp(0, 255);
          } else {
            r = g = b = 0;
          }
          out.setPixelRgba(x, y, r, g, b, alpha);
        } else {
          // 黑白
          int c = alpha > 0 ? (ga * 255 / alpha).round().clamp(0, 255) : 0;
          out.setPixelRgba(x, y, c, c, c, alpha);
        }
      }
    }

    final bytes = img.encodePng(out);
    return _saveAndCreateMeme(bytes, '.png',
      name: name ?? 'phantom_tank',
      format: 'png',
      folderId: folderId,
    );
  }

  /// 构建动画 Image 并用 [encoder] 编码为字节
  Future<Uint8List> _buildAnimation(
    List<String> srcPaths,
    int frameDurationMs,
    Uint8List Function(img.Image) encoder,
  ) async {
    if (srcPaths.isEmpty) throw ArgumentError('no source images');
    final images = <img.Image>[];
    for (final path in srcPaths) {
      final im = await decode(path);
      if (im != null) images.add(im);
    }
    if (images.isEmpty) throw StateError('all decode failed');

    // 以第一帧为基准创建动画 Image，后续帧通过 addFrame 加入
    final first = images.first;
    final anim = img.Image(
      width: first.width,
      height: first.height,
      numChannels: first.numChannels,
    );
    anim.frameDuration = frameDurationMs;
    // 复制第一帧像素
    img.compositeImage(anim, first);
    for (var i = 1; i < images.length; i++) {
      final frame = images[i];
      // 统一尺寸到第一帧（避免编码失败）
      final fitted = frame.width == anim.width && frame.height == anim.height
          ? frame
          : img.copyResize(frame, width: anim.width, height: anim.height);
      fitted.frameDuration = frameDurationMs;
      anim.addFrame(fitted);
    }
    return encoder(anim);
  }

  /// 将字节保存到存储，并创建 Meme 记录
  Future<Meme> _saveAndCreateMeme(
    Uint8List bytes,
    String ext, {
    required String name,
    required String format,
    String? folderId,
    bool isAnimated = false,
  }) async {
    final relPath = await _saveBytes(bytes, ext);
    final meme = Meme(
      id: _uuid(),
      name: name,
      filePath: relPath,
      folderId: folderId,
      tags: const [],
      createdAt: DateTime.now(),
      mimeType: _mimeOf(format),
      fileSize: bytes.length,
      type: isAnimated ? Meme.typeGif : Meme.typeImage,
    );
    await _storage.saveMeme(meme);
    return meme;
  }

  /// 将字节保存到存储，返回相对路径
  Future<String> _saveBytes(Uint8List bytes, String ext) async {
    final id = _uuid();
    final fileName = '$id$ext';
    final relPath = 'memes/$fileName';
    if (kIsWeb) {
      await webStorageSetBinary(relPath, bytes);
    } else {
      final dest = File(p.join(_storage.basePath, relPath));
      await dest.create(recursive: true);
      await dest.writeAsBytes(bytes);
    }
    return relPath;
  }

  String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = DateTime.now().millisecondsSinceEpoch.hashCode;
    return '${now}_$rand';
  }

  String _mimeOf(String format) {
    switch (format.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'gif':
        return 'image/gif';
      case 'apng':
        return 'image/apng';
      case 'png':
      default:
        return 'image/png';
    }
  }
}
