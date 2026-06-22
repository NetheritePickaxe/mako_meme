import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/database/database.dart';
import '../../data/repositories/sticker_repository.dart';

/// 统一的表情图片组件
/// - 自动从 repository 读取字节数据
/// - Native/Web 通用
class StickerImage extends StatefulWidget {
  final StickerData sticker;
  final StickerRepository repo;
  final BoxFit fit;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? margin;

  const StickerImage({
    super.key,
    required this.sticker,
    required this.repo,
    this.fit = BoxFit.cover,
    this.height,
    this.width,
    this.margin,
  });

  @override
  State<StickerImage> createState() => _StickerImageState();
}

class _StickerImageState extends State<StickerImage> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StickerImage old) {
    super.didUpdateWidget(old);
    if (old.sticker.id != widget.sticker.id) {
      _loaded = false;
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.repo.stickerBytes(widget.sticker.storedPath);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        _loaded = true;
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (!_loaded) {
      child = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        fit: widget.fit,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
      );
    } else {
      child = const Icon(Icons.image_outlined, color: Colors.grey);
    }

    if (widget.margin != null) {
      child = Padding(padding: widget.margin!, child: child);
    }

    return SizedBox(height: widget.height, width: widget.width, child: child);
  }
}
