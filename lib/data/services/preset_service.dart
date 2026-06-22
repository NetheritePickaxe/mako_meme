import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../repositories/sticker_repository.dart';

/// 首次启动时检测数据库是否为空，如果为空则生成示例表情包
class PresetService {
  final StickerRepository _repo;
  final Uuid _uuid = const Uuid();

  PresetService(this._repo);

  /// 检查并初始化预置数据
  Future<void> initializeIfNeeded() async {
    // 检查是否已有数据
    final packs = await _repo.watchAllPacks().first;
    if (packs.isNotEmpty) return;

    await _createPresetPacks();
  }

  Future<void> _createPresetPacks() async {
    // 创建默认命名空间
    final nsBasic = await _repo.createNamespace(
      name: '默认',
      icon: '😊',
      color: '7C3AED',
    );
    final nsGestures = await _repo.createNamespace(
      name: '手势',
      icon: '✌️',
      color: '3498DB',
    );

    // 创建 temp 目录用于生成图片
    final tempDir = await getTemporaryDirectory();

    // --- Pack 1: 基础表情 ---
    final pack1 = await _repo.createPack(
      name: '基础表情',
      description: '经典黄脸表情包',
      namespaceId: nsBasic.id,
      tags: ['emoji', '经典', '黄脸'],
    );

    final emojis = _getBasicEmojis();
    for (final emoji in emojis) {
      final filePath = p.join(tempDir.path, '${_uuid.v4()}.png');
      await _generateEmojiPng(filePath, emoji.text, emoji.color);
      await _repo.importSticker(
        packId: pack1.id,
        sourcePath: filePath,
        tags: emoji.tags,
      );
    }

    // --- Pack 2: 手势与动作 ---
    final pack2 = await _repo.createPack(
      name: '手势与动作',
      description: '常用手势表情',
      namespaceId: nsGestures.id,
      tags: ['手势', '动作', '常用'],
    );

    final gestures = _getGestureEmojis();
    for (final g in gestures) {
      final filePath = p.join(tempDir.path, '${_uuid.v4()}.png');
      await _generateEmojiPng(filePath, g.text, g.color);
      await _repo.importSticker(
        packId: pack2.id,
        sourcePath: filePath,
        tags: g.tags,
      );
    }
  }

  /// 生成一个简单 PNG 表情图片 (256x256)
  Future<void> _generateEmojiPng(
      String path, String emoji, int color) async {
    const size = 256.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // 背景圆
    final bgPaint = ui.Paint()
      ..color = ui.Color(color)
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, bgPaint);

    // 绘制 emoji 文字
    final textStyle = ui.TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 128,
    );
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        maxLines: 1,
      ),
    )
      ..pushStyle(textStyle)
      ..addText(emoji);

    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: size));
    // 居中绘制文字
    canvas.drawParagraph(
      paragraph,
      Offset(0, (size - paragraph.height) / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      await File(path).writeAsBytes(byteData.buffer.asUint8List());
    }
  }

  static List<_EmojiDef> _getBasicEmojis() => [
        _EmojiDef('😀', 0xFFFFD93D, ['笑', '开心', '哈哈']),
        _EmojiDef('😂', 0xFFFFD93D, ['笑哭', '笑', '哈哈哈']),
        _EmojiDef('😍', 0xFFFFD93D, ['喜欢', '爱心', '花痴']),
        _EmojiDef('😎', 0xFFFFD93D, ['酷', '墨镜', '自信']),
        _EmojiDef('🤔', 0xFFFFD93D, ['思考', '疑惑', '想想']),
        _EmojiDef('😭', 0xFFFFD93D, ['哭', '难过', '伤心']),
        _EmojiDef('😡', 0xFFFF4444, ['生气', '愤怒', '怒']),
        _EmojiDef('🥰', 0xFFFFD93D, ['爱心', '喜欢', '甜蜜']),
        _EmojiDef('🤣', 0xFFFFD93D, ['笑', '滚地', '哈哈哈']),
        _EmojiDef('😱', 0xFFFFD93D, ['震惊', '惊讶', 'OMG']),
        _EmojiDef('👍', 0xFFFFD93D, ['赞', '好', '认可']),
        _EmojiDef('🎉', 0xFF8B5CF6, ['庆祝', '恭喜', '派对']),
      ];

  static List<_EmojiDef> _getGestureEmojis() => [
        _EmojiDef('👍', 0xFF3498DB, ['赞', '好', '认可']),
        _EmojiDef('👎', 0xFFE74C3C, ['踩', '不好', '反对']),
        _EmojiDef('👏', 0xFF3498DB, ['鼓掌', '赞', '恭喜']),
        _EmojiDef('🙌', 0xFF3498DB, ['举手', '庆祝', '开心']),
        _EmojiDef('💪', 0xFFE67E22, ['加油', '力量', '努力']),
        _EmojiDef('✌️', 0xFF2ECC71, ['耶', '胜利', 'V']),
        _EmojiDef('🤝', 0xFF3498DB, ['握手', '合作', '你好']),
        _EmojiDef('🙏', 0xFF9B59B6, ['拜托', '谢谢', '祈祷']),
      ];
}

class _EmojiDef {
  final String text;
  final int color;
  final List<String> tags;
  const _EmojiDef(this.text, this.color, this.tags);
}
