import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 精灵图层类别
class SpriteCategory {
  static const String base = 'base';           // 基础层（必选，立绘身体/底图）
  static const String expression = 'expression'; // 表情差分
  static const String outfit = 'outfit';       // 服装差分
  static const String accessory = 'accessory';  // 饰品/其他

  static const List<String> all = [base, expression, outfit, accessory];

  /// 猜测图层类别（根据名称）
  static String guess(String name) {
    final n = name.toLowerCase();
    // 表情关键词
    const exprKeywords = [
      'face', '表情', 'eye', 'eyes', 'mouth', '眉', '眼', '嘴', '笑', 'smile',
      'angry', '怒', 'sad', '悲', 'cry', '哭', 'surprise', '惊', 'happy', '喜',
      'blush', '红', 'wink', '眨', 'expression', 'emote',
    ];
    // 服装关键词
    const outfitKeywords = [
      'cloth', 'clothes', 'costume', 'dress', 'outfit', 'uniform', '服装',
      '衣服', '裙', 'shirt', 'jacket', 'coat', '套', '装',
    ];
    // 饰品关键词
    const accKeywords = [
      'accessory', 'accessories', 'hat', 'glasses', 'ribbon', 'bow', 'earring',
      'necklace', 'ring', '饰', '帽', '眼镜', '丝带', '蝴蝶结', '耳环', '项链',
    ];
    // 基础层关键词
    const baseKeywords = [
      'base', 'body', 'skin', '基础', '身体', '底', '本体', 'back', 'hair',
      '头发', 'bg',
    ];
    for (final k in exprKeywords) {
      if (n.contains(k)) return expression;
    }
    for (final k in outfitKeywords) {
      if (n.contains(k)) return outfit;
    }
    for (final k in accKeywords) {
      if (n.contains(k)) return accessory;
    }
    for (final k in baseKeywords) {
      if (n.contains(k)) return base;
    }
    return expression; // 默认按表情差分处理
  }
}

/// 精灵图层信息
class SpriteLayer {
  final String name;
  final String path;       // 相对存储路径（memes/xxx.png）
  final String category;   // SpriteCategory
  final bool visible;      // 当前是否可见
  final int zOrder;        // 层级（数值越大越靠上）

  const SpriteLayer({
    required this.name,
    required this.path,
    required this.category,
    required this.visible,
    required this.zOrder,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'path': path,
    'category': category,
    'visible': visible,
    'zOrder': zOrder,
  };

  factory SpriteLayer.fromMap(Map<String, dynamic> m) => SpriteLayer(
    name: m['name'] as String? ?? '',
    path: m['path'] as String? ?? '',
    category: m['category'] as String? ?? SpriteCategory.expression,
    visible: m['visible'] as bool? ?? true,
    zOrder: m['zOrder'] as int? ?? 0,
  );
}

/// pjson 解析结果
class PjsonParseResult {
  /// 解析出的图层（path 字段为 pjson 中引用的相对文件名，需后续匹配实际文件）
  final List<Map<String, dynamic>> layers;
  final int width;
  final int height;
  final String? name;
  const PjsonParseResult({
    required this.layers,
    required this.width,
    required this.height,
    this.name,
  });
}

class SpriteService {
  /// 解析 krkr pjson 文件内容（JSON 字符串）
  ///
  /// pjson 格式因工具而异，本解析器采用宽松策略：
  /// - 优先查找 `layers` / `parts` / `elements` 数组
  /// - 每层查找 `name`/`label`、`image`/`src`/`file`、`x`/`y`、`category`/`type`
  /// - 宽高优先取 `width`/`height`，其次从图层边界推断
  static PjsonParseResult? parsePjson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      if (data is! Map<String, dynamic>) return null;

      // 提取名称
      final name = data['name'] as String? ?? data['title'] as String?;

      // 提取宽高
      int width = _parseInt(data['width']) ?? _parseInt(data['w']) ?? 0;
      int height = _parseInt(data['height']) ?? _parseInt(data['h']) ?? 0;

      // 查找图层数组（多种可能字段名）
      List<dynamic>? rawLayers;
      for (final key in ['layers', 'parts', 'elements', 'sprites', 'images']) {
        if (data[key] is List) {
          rawLayers = data[key] as List;
          break;
        }
      }
      if (rawLayers == null || rawLayers.isEmpty) return null;

      final layers = <Map<String, dynamic>>[];
      int maxRight = 0;
      int maxBottom = 0;
      for (var i = 0; i < rawLayers.length; i++) {
        final item = rawLayers[i];
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);

        // 图层名
        final layerName = (m['name'] ?? m['label'] ?? m['id'] ?? 'layer_$i').toString();
        // 图片文件名（pjson 中引用的相对路径）
        final imageFile = (m['image'] ?? m['src'] ?? m['file'] ?? m['path'] ?? m['url'])
            ?.toString();
        if (imageFile == null || imageFile.isEmpty) continue;

        // 偏移
        final x = _parseInt(m['x']) ?? _parseInt(m['offsetX']) ?? _parseInt(m['left']) ?? 0;
        final y = _parseInt(m['y']) ?? _parseInt(m['offsetY']) ?? _parseInt(m['top']) ?? 0;
        final w = _parseInt(m['width']) ?? _parseInt(m['w']) ?? 0;
        final h = _parseInt(m['height']) ?? _parseInt(m['h']) ?? 0;

        // 类别
        String category = (m['category'] ?? m['type'] ?? '').toString();
        if (!SpriteCategory.all.contains(category)) {
          category = SpriteCategory.guess(layerName);
        }

        if (x + w > maxRight) maxRight = x + w;
        if (y + h > maxBottom) maxBottom = y + h;

        layers.add({
          'name': layerName,
          'imageFile': imageFile, // pjson 引用的相对文件名，需后续匹配
          'category': category,
          'visible': m['visible'] != false,
          'zOrder': i,
          'offsetX': x,
          'offsetY': y,
          'width': w,
          'height': h,
        });
      }

      if (layers.isEmpty) return null;

      // 若未指定宽高，用图层边界推断
      if (width == 0) width = maxRight;
      if (height == 0) height = maxBottom;

      return PjsonParseResult(
        layers: layers,
        width: width,
        height: height,
        name: name,
      );
    } catch (_) {
      return null;
    }
  }

  /// 将多张图片合成为预览 PNG（用于卡片缩略图）
  /// 按图层 zOrder 叠加，仅合成 visible=true 的图层
  static Uint8List? composePreview(List<Uint8List> layerBytes, List<int> zOrders) {
    try {
      if (layerBytes.isEmpty) return null;

      // 按 zOrder 排序
      final indexed = <MapEntry<int, Uint8List>>[];
      for (var i = 0; i < layerBytes.length; i++) {
        indexed.add(MapEntry(zOrders.length > i ? zOrders[i] : i, layerBytes[i]));
      }
      indexed.sort((a, b) => a.key.compareTo(b.key));

      // 解码第一层作为底
      img.Image? composite;
      for (final entry in indexed) {
        final decoded = img.decodeImage(entry.value);
        if (decoded == null) continue;
        if (composite == null) {
          composite = decoded;
        } else {
          // 叠加到合成图（居中对齐，尺寸不足时扩展画布）
          if (decoded.width > composite.width || decoded.height > composite.height) {
            final newW = decoded.width > composite.width ? decoded.width : composite.width;
            final newH = decoded.height > composite.height ? decoded.height : composite.height;
            final expanded = img.Image(width: newW, height: newH);
            img.compositeImage(expanded, composite);
            img.compositeImage(expanded, decoded);
            composite = expanded;
          } else {
            img.compositeImage(composite, decoded);
          }
        }
      }
      if (composite == null) return null;
      return Uint8List.fromList(img.encodePng(composite));
    } catch (_) {
      return null;
    }
  }

  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
