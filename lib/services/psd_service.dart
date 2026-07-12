import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// PSD 解析结果
class PsdParseResult {
  /// 合成预览图（PNG 字节流）
  final Uint8List? compositePng;
  final int width;
  final int height;
  /// 图层信息：name / visible / left / top / right / bottom
  final List<Map<String, dynamic>> layers;
  const PsdParseResult({
    this.compositePng,
    required this.width,
    required this.height,
    required this.layers,
  });
}

class PsdService {
  /// 解析 PSD 字节，返回合成预览（PNG）和图层信息
  /// 大文件可能 OOM，调用方应在 isolate 中执行或捕获异常
  static PsdParseResult? parse(Uint8List bytes) {
    try {
      final decoder = img.PsdDecoder();
      final psd = decoder.decodePsd(bytes);
      if (psd == null) return null;

      final width = psd.width;
      final height = psd.height;

      // 提取合成图（优先用 mergedImage，否则解码）
      Uint8List? compositePng;
      img.Image? merged = psd.mergedImage ?? decoder.decode(bytes);
      if (merged != null) {
        compositePng = Uint8List.fromList(img.encodePng(merged));
      }

      // 提取图层信息（扁平化遍历，包括子图层）
      final layers = <Map<String, dynamic>>[];
      void visitLayer(img.PsdLayer layer, int depth) {
        layers.add({
          'name': layer.name ?? '未命名图层',
          'visible': (layer.flags & img.PsdFlag.hidden) == 0,
          'left': layer.left ?? 0,
          'top': layer.top ?? 0,
          'right': layer.right,
          'bottom': layer.bottom,
          'width': layer.width,
          'height': layer.height,
          'depth': depth,
          'hasImage': layer.layerImage != null,
        });
        for (final child in layer.children) {
          visitLayer(child, depth + 1);
        }
      }
      for (final layer in psd.layers) {
        visitLayer(layer, 0);
      }

      return PsdParseResult(
        compositePng: compositePng,
        width: width,
        height: height,
        layers: layers,
      );
    } catch (_) {
      return null;
    }
  }
}
