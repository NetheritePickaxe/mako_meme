import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/locale_provider.dart';
import '../l10n/l10n.dart';
import '../services/storage_service.dart';

/// 横屏模式下的左侧大图预览面板
/// 显示当前选中 meme 的大图、名称、类型、标签等信息
class MemePreviewPanel extends StatefulWidget {
  final Meme? meme;
  final VoidCallback? onClose;

  const MemePreviewPanel({
    super.key,
    required this.meme,
    this.onClose,
  });

  @override
  State<MemePreviewPanel> createState() => _MemePreviewPanelState();
}

class _MemePreviewPanelState extends State<MemePreviewPanel> {
  Uint8List? _bytes;
  File? _file;
  bool _loading = false;

  @override
  void didUpdateWidget(MemePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meme?.id != widget.meme?.id) {
      _bytes = null;
      _file = null;
      _loading = false;
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    if (_loading) return;
    final m = widget.meme;
    if (m == null) return;
    if (!m.isImageType || m.displayPath.isEmpty) return;
    _loading = true;
    final storage = context.read<StorageService>();
    if (kIsWeb) {
      storage.readMemeBytes(m.displayPath).then((b) {
        if (mounted) setState(() { _bytes = b; _loading = false; });
      }, onError: (_) {
        if (mounted) setState(() => _loading = false);
      });
    } else {
      final f = storage.getMemeFile(m.displayPath);
      if (f == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      f.exists().then((exists) {
        if (mounted) setState(() { _file = exists ? f : null; _loading = false; });
      }, onError: (_) {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.read<LocaleProvider>().l10n;
    final m = widget.meme;

    if (m == null) {
      return Container(
        width: 360,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(l10n.tr('preview_empty'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 4),
              Text(l10n.tr('preview_empty_hint'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline.withValues(alpha: 0.7))),
            ],
          ),
        ),
      );
    }

    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：标题栏
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Icon(_typeIcon(m), size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                    tooltip: l10n.tr('close'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          // 中部：预览大图
          Expanded(
            child: _buildPreviewArea(theme, m),
          ),
          // 底部：信息区
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: _buildInfo(theme, l10n, m),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea(ThemeData theme, Meme m) {
    // 非图片类或无图片路径（文本 emoji）：显示文字/占位
    if (!m.isImageType || m.displayPath.isEmpty) {
      if (m.isTextLike) {
        final content = m.textContent ?? '';
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            content.isEmpty ? l10nForContext().tr('no_text_content') : content,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: m.isNovel ? 14 : 16,
              height: m.isNovel ? 1.8 : 1.5,
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_typeIcon(m), size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(_typeLabel(m), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
      );
    }

    final hasData = _bytes != null || _file != null;
    if (!hasData) {
      return Center(
        child: Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.outline),
      );
    }

    // 漫画：显示首页 + 页数徽章
    if (m.isManga) {
      return Stack(
        children: [
          Positioned.fill(child: _buildImage(theme, m)),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.collections, size: 12, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('${m.pages.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _buildImage(theme, m);
  }

  Widget _buildImage(ThemeData theme, Meme m) {
    // SVG
    if (m.isVector) {
      final svgBytes = _bytes ?? _file?.readAsBytesSync();
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: svgBytes != null
              ? SvgPicture.memory(svgBytes, fit: BoxFit.contain)
              : const SizedBox.shrink(),
        ),
      );
    }
    // 普通图片
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 6.0,
        child: _file != null
            ? Image.file(_file!, fit: BoxFit.contain)
            : Image.memory(_bytes!, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildInfo(ThemeData theme, L10n l10n, Meme m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签
        if (m.tags.isNotEmpty) ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: m.tags.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('#$t', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
            )).toList(),
          ),
          const SizedBox(height: 8),
        ],
        // 元数据
        DefaultTextStyle(
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)) ?? const TextStyle(fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.fileSize > 0) Text('${l10n.tr('size')}: ${_formatSize(m.fileSize)}'),
              if (m.width > 0 && m.height > 0) Text('${l10n.tr('dimensions')}: ${m.width}×${m.height}'),
              Text('${l10n.tr('type')}: ${_typeLabel(m)}'),
              Text('${l10n.tr('created_at')}: ${_formatDate(m.createdAt)}'),
            ],
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _typeLabel(Meme m) {
    final l10n = context.read<LocaleProvider>().l10n;
    switch (m.type) {
      case Meme.typeEmoji: return l10n.tr('type_emoji');
      case Meme.typeGif: return l10n.tr('type_gif');
      case Meme.typeText: return l10n.tr('type_text');
      case Meme.typeNovel: return l10n.tr('type_novel');
      case Meme.typeManga: return l10n.tr('type_manga');
      case Meme.typePortrait: return l10n.tr('type_portrait');
      case Meme.typeCg: return l10n.tr('type_cg');
      case Meme.typeCharacterCard: return l10n.tr('type_character_card');
      case Meme.typeVector: return l10n.tr('type_vector');
      case Meme.typePsd: return l10n.tr('type_psd');
      case Meme.typePdf: return l10n.tr('type_pdf');
      default: return l10n.tr('type_image');
    }
  }

  IconData _typeIcon(Meme m) {
    switch (m.type) {
      case Meme.typeEmoji: return Icons.face;
      case Meme.typeGif: return Icons.gif;
      case Meme.typeText:
      case Meme.typeNovel: return Icons.text_fields;
      case Meme.typeManga: return Icons.photo_library;
      case Meme.typePortrait: return Icons.portrait;
      case Meme.typeCg: return Icons.photo_library;
      case Meme.typeCharacterCard: return Icons.person_outline;
      case Meme.typeVector: return Icons.grain;
      case Meme.typePsd: return Icons.layers;
      case Meme.typePdf: return Icons.picture_as_pdf;
      default: return Icons.image;
    }
  }

  L10n l10nForContext() => context.read<LocaleProvider>().l10n;
}
