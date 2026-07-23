import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/settings_provider.dart';
import '../services/storage_service.dart';
import '../screens/meme_viewer_screen.dart';
import '../utils/lru_cache.dart';

class MemeCard extends StatefulWidget {
  final Meme meme;
  final void Function(Meme dragged, Meme target)? onReorder;
  /// 横屏预览模式：点击卡片选中预览（替代默认的复制/打开行为）
  final bool previewMode;
  /// 当前是否被选中预览
  final bool isPreviewSelected;

  const MemeCard({
    super.key,
    required this.meme,
    this.onReorder,
    this.previewMode = false,
    this.isPreviewSelected = false,
  });

  @override
  State<MemeCard> createState() => _MemeCardState();
}

class _MemeCardState extends State<MemeCard> {
  Uint8List? _bytes;       // Web 端使用
  File? _file;             // 原生端使用
  bool _loading = true;
  double _aspectRatio = 1.0;
  Offset? _lastTapPosition; // 用于长按呼出菜单时定位

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBytes();
  }

  /// meme 更新时（如 thumbPath 变化），重置状态重新加载
  @override
  void didUpdateWidget(covariant MemeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meme.id != widget.meme.id ||
        oldWidget.meme.displayPath != widget.meme.displayPath) {
      _bytes = null;
      _file = null;
      _loading = true;
      _aspectRatio = 1.0;
      _loadBytes();
    }
  }

  /// 实际用于显示的路径：有缩略图（PSD/ICO/TIF）时用 thumbPath，否则用 filePath
  String get _displayPath => widget.meme.displayPath;

  void _loadBytes() {
    if (!_loading) return;
    final m = widget.meme;
    // PDF 仅在有缩略图（导入时已渲染封面）时才加载缩略图字节
    if (m.isPdf) {
      if (m.thumbPath == null || m.thumbPath!.isEmpty) {
        _loading = false;
        return;
      }
      // 走和图片相同的加载路径，displayPath 已指向 thumbPath
    }
    final storage = context.read<StorageService>();
    if ((m.isImageType || (m.isPdf && m.thumbPath != null)) && _displayPath.isNotEmpty) {
      // 优先用导入时记录的宽高，避免每次都解析文件头
      if (m.width > 0 && m.height > 0) {
        _aspectRatio = m.width / m.height;
      }
      if (kIsWeb) {
        final cached = thumbCache.get(_displayPath);
        if (cached != null) {
          _bytes = cached;
          _loading = false;
          if (mounted) setState(() {});
          return;
        }
        // Web：读 bytes
        debugPrint('[MakoCard] _loadBytes WEB: id=${m.id}, displayPath="$_displayPath", type=${m.type}');
        storage.readMemeBytes(_displayPath).then((b) {
          thumbCache.put(_displayPath, b);
          if (mounted) {
            setState(() {
              _bytes = b;
              _loading = false;
            });
            debugPrint('[MakoCard] _loadBytes WEB done: id=${m.id}, '
                'bytes=${b == null ? "null" : b.length.toString()}');
            // 仅当 meme 未记录宽高时才从头解析
            if (b != null && (m.width == 0 || m.height == 0)) {
              _loadAspectRatioFromBytes(b);
            }
          }
        }, onError: (e) {
          debugPrint('[MakoCard] _loadBytes WEB ERROR: id=${m.id}, error=$e');
          if (mounted) setState(() { _loading = false; });
        });
      } else {
        // 原生：同步设置 _file，靠 Image.file 的 errorBuilder 处理文件不存在的情况
        // 这样首次 build 就能命中 Flutter ImageCache，避免灰色闪烁
        final f = storage.getMemeFile(_displayPath);
        _file = f;
        _loading = false;
        // 仅当 meme 未记录宽高时才异步解析文件头
        if (f != null && (m.width == 0 || m.height == 0)) {
          _loadAspectRatioFromFile();
        }
      }
    } else {
      debugPrint('[MakoCard] _loadBytes SKIP: id=${m.id}, '
          'isImageType=${m.isImageType}, displayPath="$_displayPath", type=${m.type}');
      _loading = false;
    }
  }

  void _loadAspectRatioFromBytes(Uint8List bytes) {
    // 从文件头解析宽高，不解码整图（避免 OOM）
    try {
      final dims = StorageService.parseImageDimensionsFromHeader(bytes);
      if (dims != null && dims.width > 0 && dims.height > 0 && mounted) {
        setState(() => _aspectRatio = dims.width / dims.height);
      }
    } catch (_) {}
  }

  Future<void> _loadAspectRatioFromFile() async {
    // 原生端只读 64KB 头部解析宽高，不解码整图
    try {
      final storage = context.read<StorageService>();
      final ratio = await storage.getImageAspectRatio(_displayPath);
      if (mounted && ratio != null && ratio > 0 && ratio.isFinite) {
        setState(() => _aspectRatio = ratio);
      }
    } catch (_) {}
  }

  bool get _isDesktop {
    if (kIsWeb) return true;
    final p = Theme.of(context).platform;
    return p == TargetPlatform.windows || p == TargetPlatform.linux || p == TargetPlatform.macOS;
  }

  bool get _isSquare =>
      widget.meme.type == Meme.typeEmoji;

  double get _effectiveAspectRatio {
    if (_isSquare) return 1.0;
    if (widget.meme.type == Meme.typeText) {
      // 文字卡片不用固定比例，由内容决定高度
      return double.nan;
    }
    if (_aspectRatio.isNaN || _aspectRatio.isInfinite || _aspectRatio <= 0) return 1.0;
    return _aspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final isSelected = prov.selected.contains(widget.meme.id);
    final isMulti = prov.isMulti;
    final theme = Theme.of(context);
    final canReorder = widget.onReorder != null;

    // 桌面端：长按拖拽（用于排序或拖入文件夹），左键复制，右键菜单
    if (_isDesktop) {
      final card = GestureDetector(
        onTap: isMulti
            ? () => prov.toggleSelect(widget.meme.id)
            : (widget.previewMode ? _previewSelect : _copyToClipboard),
        onDoubleTap: widget.previewMode && !isMulti ? _openViewer : null,
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        child: _buildInner(prov, isSelected, isMulti, theme),
      );
      return LongPressDraggable<Meme>(
        data: widget.meme,
        feedback: _buildFeedback(),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildAspectRatioCard(prov, isSelected, isMulti, theme),
        ),
        onDragStarted: () => HapticFeedback.mediumImpact(),
        child: card,
      );
    }

    // 移动端：多选模式下长按拖拽排序
    if (isMulti && canReorder) {
      final inner = _buildInner(prov, isSelected, isMulti, theme);
      return LongPressDraggable<Meme>(
        data: widget.meme,
        feedback: _buildFeedback(),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildAspectRatioCard(prov, isSelected, isMulti, theme),
        ),
        onDragStarted: () => HapticFeedback.mediumImpact(),
        child: GestureDetector(
          onTap: () => prov.toggleSelect(widget.meme.id),
          child: inner,
        ),
      );
    }

    // 移动端普通模式：点击预览，长按分享或呼出菜单（按设置）
    final settings = context.read<SettingsProvider>();
    return GestureDetector(
      onTapDown: (details) => _lastTapPosition = details.globalPosition,
      onTap: isMulti
          ? () => prov.toggleSelect(widget.meme.id)
          : (widget.previewMode ? _previewSelect : _openViewer),
      onDoubleTap: widget.previewMode && !isMulti ? _openViewer : null,
      onLongPress: isMulti
          ? null
          : () {
              HapticFeedback.mediumImpact();
              if (settings.mobileLongPressIsMenu) {
                _showContextMenu(_lastTapPosition ?? Offset.zero);
              } else {
                _shareMeme();
              }
            },
      child: _buildInner(prov, isSelected, isMulti, theme),
    );
  }

  /// 横屏预览模式：点击卡片更新预览面板
  void _previewSelect() {
    final prov = context.read<MemeProvider>();
    prov.setPreviewMeme(widget.meme);
  }

  /// 包裹拖放目标，用于排序：拖入另一张卡片时触发 onReorder
  Widget _buildInner(MemeProvider prov, bool isSelected, bool isMulti, ThemeData theme) {
    final card = _buildAspectRatioCard(prov, isSelected, isMulti, theme);
    if (widget.onReorder == null) return card;
    return DragTarget<Meme>(
      onAcceptWithDetails: (details) {
        if (details.data.id != widget.meme.id) {
          widget.onReorder!(details.data, widget.meme);
        }
      },
      builder: (ctx, candidate, rejected) {
        if (candidate.isEmpty) return card;
        return Stack(
          children: [
            card,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 表情卡片固定 1:1，文字卡片自适应高度，图片卡片按真实宽高比
  /// 卡片信息（名称/标签/类型/后缀）以透明渐变层叠加在图片底部
  Widget _buildAspectRatioCard(MemeProvider prov, bool isSelected, bool isMulti, ThemeData theme) {
    final ratio = _effectiveAspectRatio;
    if (ratio.isNaN) {
      // 文字卡片：由内容决定高度，不强制比例
      return _buildCard(context, prov, isSelected, isMulti, theme);
    }
    return AspectRatio(
      aspectRatio: ratio,
      child: _buildCard(context, prov, isSelected, isMulti, theme),
    );
  }

  /// 卡片底部叠加的信息层：名称第一行（大），标签/类型/后缀第二行（小，可换行）
  Widget _buildInfoOverlay(ThemeData theme) {
    final settings = context.watch<SettingsProvider>();
    final l10n = context.read<LocaleProvider>().l10n;
    final m = widget.meme;
    final showName = settings.showCardName;
    final showTags = settings.showCardTags && m.tags.isNotEmpty;
    final showType = settings.showCardType;
    final showExt = settings.showCardExt && m.extension.isNotEmpty;
    if (!showName && !showTags && !showType && !showExt) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showName)
                Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              if (showTags || showType || showExt) ...[
                const SizedBox(height: 2),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    if (showTags)
                      Text(
                        m.tags.map((t) => '#$t').join(' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    if (showType)
                      _overlayChip(l10n.tr(m.typeLabelKey)),
                    if (showExt)
                      _overlayChip(m.extension.toUpperCase()),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlayChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        decoration: TextDecoration.none,
      ),
    ),
  );

  Widget _buildFeedback() {
    // 文字卡片：反馈显示文字
    if (widget.meme.type == Meme.typeText) {
      return Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160, maxHeight: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(8),
              child: Text(
                widget.meme.textContent ?? '',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    // 表情卡片：反馈显示表情
    if (widget.meme.type == Meme.typeEmoji) {
      return Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 100,
          height: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: Text(
                widget.meme.textContent ?? '',
                style: const TextStyle(fontSize: 28, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    // 图片卡片：反馈显示缩略图
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 100,
        height: 100,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildThumbnail(fit: BoxFit.cover),
        ),
      ),
    );
  }

  /// 统一的缩略图渲染：PDF 显示图标，SVG 用 SvgPicture，其他用 Image.file/memory（带 cacheWidth 防止 OOM）
  Widget _buildThumbnail({required BoxFit fit}) {
    // PDF：有缩略图显示封面，无缩略图显示图标
    if (widget.meme.isPdf) {
      if (widget.meme.thumbPath == null ||
          widget.meme.thumbPath!.isEmpty ||
          (_bytes == null && _file == null)) {
        return _formatPlaceholder(Icons.picture_as_pdf, 'PDF');
      }
      // 走和普通图片相同的渲染分支（下方位图逻辑）
    }
    // SVG 矢量图：用 flutter_svg 渲染，无限缩放不失真
    if (widget.meme.isVector) {
      final svgBytes = _bytes ?? _file?.readAsBytesSync();
      if (svgBytes != null) {
        return SvgPicture.memory(
          svgBytes,
          fit: fit,
          placeholderBuilder: (_) => _placeholder(),
        );
      }
      return _placeholder();
    }
    // PSD 没有合成预览时的占位
    if (widget.meme.isPsd && _file == null && _bytes == null) {
      return _formatPlaceholder(Icons.layers, 'PSD');
    }
    // 立绘/CG 精灵图：未生成预览时的占位
    if (widget.meme.isSprite && _file == null && _bytes == null) {
      return _formatPlaceholder(Icons.face_retouching_natural, 'SPRITE');
    }
    // 普通位图：原生端用 Image.file，Web 端用 Image.memory，都加 cacheWidth
    // 当原始图片尺寸很小（≤64px）时视为像素图，用最近邻插值保持清晰
    final isPixelArt = widget.meme.width > 0 && widget.meme.width <= 128 &&
        widget.meme.height > 0 && widget.meme.height <= 128;
    final filterQuality = isPixelArt ? FilterQuality.none : FilterQuality.low;
    if (_file != null) {
      return Image.file(
        _file!,
        fit: fit,
        cacheWidth: 512,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: fit,
        cacheWidth: 512,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return Container(color: Colors.grey.shade300);
  }

  Widget _placeholder() => Container(
    color: Colors.grey.shade200,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.red.shade300, size: 32),
          const SizedBox(height: 4),
          Text(
            context.read<LocaleProvider>().l10n.tr('lost_label'),
            style: TextStyle(
              fontSize: 10,
              color: Colors.red.shade400,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  /// 通用格式占位符：图标 + 格式标签
  Widget _formatPlaceholder(IconData icon, String label) => Container(
    color: Colors.grey.shade100,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey, size: 32),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    ),
  );

  Widget _buildCard(BuildContext context, MemeProvider prov, bool isSelected, bool isMulti, ThemeData theme) {
    final cs = Theme.of(context).colorScheme;
    // 选中边框采用 Positioned.fill overlay 而非外层 Container.border，
    // 避免边框出现时挤压内容导致缩小动画 + 内圆角与外边框圆角不一致漏白角
    final borderOverlay = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: cs.primary, width: 3)
                : widget.isPreviewSelected
                    ? Border.all(color: cs.tertiary, width: 2)
                    : null,
          ),
        ),
      ),
    );

    // 文字卡片：不用 Stack(fit: expand)，让内容自适应高度
    if (widget.meme.type == Meme.typeText) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Container(
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.meme.textContent ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (widget.meme.isFavorite)
                Positioned(top: 6, right: 6,
                  child: Container(padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle),
                    child: Icon(Icons.favorite, size: 14, color: cs.onTertiary),
                  ),
                ),
              if (isMulti)
                Positioned(top: 6, left: 6,
                  child: Container(padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : Colors.white.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: isSelected ? cs.primary : Colors.grey.shade400, width: 2),
                    ),
                    child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : const SizedBox(width: 14, height: 14),
                  ),
                ),
              Positioned(bottom: 6, left: 6,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: cs.secondary.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                  child: Text(context.read<LocaleProvider>().l10n.tr('text_label'),
                    style: TextStyle(color: cs.onSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              borderOverlay,
            ],
          ),
        ),
      );
    }

    // 图片/表情等卡片：用 Stack(fit: expand) 撑满
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.meme.isPdf)
                _buildThumbnail(fit: BoxFit.cover)
              else if (widget.meme.isImageType && _loading)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else if (widget.meme.isImageType && (_file != null || _bytes != null))
                _buildThumbnail(fit: BoxFit.cover)
              else if (widget.meme.isImageType && widget.meme.displayPath.isNotEmpty)
                Container(
                  color: Colors.grey.shade200,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_not_supported_outlined, size: 32, color: Colors.red.shade300),
                        const SizedBox(height: 4),
                        Text(context.read<LocaleProvider>().l10n.tr('lost_label'),
                            style: TextStyle(fontSize: 10, color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.all(8),
                  child: Center(child: Text(
                    widget.meme.textContent ?? '',
                    style: TextStyle(fontSize: widget.meme.type == Meme.typeEmoji ? 28 : 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black87),
                    textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 4,
                  )),
                ),
              if (widget.meme.isFavorite)
                Positioned(top: 6, right: 6,
                  child: Container(padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiary, shape: BoxShape.circle),
                    child: Icon(Icons.favorite, size: 14, color: Theme.of(context).colorScheme.onTertiary),
                  ),
                ),
              if (widget.meme.isManga)
                Positioned(top: 6, right: widget.meme.isFavorite ? 30 : 6,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.collections, size: 12, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('${widget.meme.pages.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              if (widget.meme.isSpriteSheet && widget.meme.spriteSheet != null)
                Positioned(top: 6, right: widget.meme.isFavorite || widget.meme.isManga ? 60 : 6,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.view_carousel, size: 12, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('${widget.meme.spriteSheet!['frameCount']}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              if (isMulti)
                Positioned(top: 6, left: 6,
                  child: Container(padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400, width: 2),
                    ),
                    child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : const SizedBox(width: 14, height: 14),
                  ),
                ),
              if (widget.meme.type != Meme.typeImage &&
                  (context.watch<MemeProvider>().typeFilter.isEmpty &&
                      context.watch<MemeProvider>().tagFilter.isEmpty &&
                      context.watch<MemeProvider>().moodFilter == null ||
                      context.watch<SettingsProvider>().showCardType))
                Positioned(bottom: 6, left: 6,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                    child: Text(_typeLabel(widget.meme.type),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              // 底部叠加信息层（名称/标签/类型/后缀）
              _buildInfoOverlay(Theme.of(context)),
              borderOverlay,
            ],
          ),
        ),
    );
  }

  void _copyToClipboard() {
    final l10n = context.read<LocaleProvider>().l10n;
    final hasData = _bytes != null || _file != null;
    if (widget.meme.isImageType && widget.meme.displayPath.isNotEmpty && !hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('lost')), duration: const Duration(seconds: 1)),
      );
      return;
    }
    // Flutter 无原生图片剪贴板支持（需 platform channel），此处简化处理
    Clipboard.setData(ClipboardData(text: widget.meme.name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('copied', args: {'name': widget.meme.name})), duration: const Duration(seconds: 1)),
    );
  }

  void _openViewer() {
    final prov = context.read<MemeProvider>();
    final memes = prov.memes;
    final index = memes.indexWhere((m) => m.id == widget.meme.id);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MemeViewerScreen(
        memes: memes,
        initialIndex: index >= 0 ? index : 0,
      ),
    ));
  }

  Future<void> _shareMeme() async {
    final m = widget.meme;
    final storage = context.read<StorageService>();
    if (kIsWeb) {
      // Web：从内存读取字节分享
      final bytes = await storage.readMemeBytes(m.filePath);
      if (bytes == null) return;
      final ext = p.extension(m.filePath).replaceFirst('.', '');
      await Share.shareXFiles([
        XFile.fromData(bytes, name: '${m.name}.$ext', mimeType: 'image/$ext'),
      ]);
    } else {
      // 原生：直接分享文件
      final file = storage.getMemeFile(m.filePath);
      if (file == null || !await file.exists()) return;
      await Share.shareXFiles([XFile(file.path)]);
    }
  }

  void _showContextMenu(Offset tapPosition) {
    final l10n = context.read<LocaleProvider>().l10n;
    final isReadOnly = false;
    showMenu(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        tapPosition & const Size(1, 1),
        Offset.zero & MediaQuery.of(context).size,
      ),
      items: <PopupMenuEntry<String>>[
        if (!isReadOnly && _bytes == null && _file == null && !_loading)
          PopupMenuItem<String>(
            value: 'reimport',
            child: ListTile(leading: const Icon(Icons.refresh), title: Text(l10n.tr('reimport')), dense: true),
          ),
        if (_bytes != null || _file != null)
          PopupMenuItem<String>(
            value: 'preview',
            child: ListTile(leading: const Icon(Icons.zoom_in), title: Text(l10n.tr('preview_large')), dense: true),
          ),
        if (!isReadOnly) PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(leading: const Icon(Icons.edit), title: Text(l10n.tr('rename')), dense: true),
        ),
        if (!isReadOnly) PopupMenuItem<String>(
          value: 'type',
          child: ListTile(leading: const Icon(Icons.label_outline), title: Text(l10n.tr('select_category')), dense: true),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: ListTile(leading: const Icon(Icons.copy), title: Text(l10n.tr('copy')), dense: true),
        ),
        PopupMenuItem<String>(
          value: 'share',
          child: ListTile(leading: const Icon(Icons.share), title: Text(l10n.tr('share')), dense: true),
        ),
        if (!isReadOnly) PopupMenuItem<String>(
          value: 'favorite',
          child: ListTile(
            leading: Icon(Icons.favorite, color: widget.meme.isFavorite ? Colors.red : null),
            title: Text(widget.meme.isFavorite ? l10n.tr('unfavorite') : l10n.tr('favorite')),
            dense: true,
          ),
        ),
        if (!isReadOnly) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'multi_select',
            child: ListTile(leading: const Icon(Icons.checklist), title: Text(l10n.tr('multi_select')), dense: true),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: Text(l10n.tr('delete'), style: const TextStyle(color: Colors.red)), dense: true),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'preview': _openViewer(); break;
        case 'reimport': _reimport(); break;
        case 'rename': _showRenameDialog(); break;
        case 'type': _showTypeDialog(); break;
        case 'copy': _copyToClipboard(); break;
        case 'share': _shareMeme(); break;
        case 'favorite':
          if (mounted) context.read<MemeProvider>().toggleFavorite(widget.meme.id);
          break;
        case 'multi_select':
          // 进入多选模式并选中当前卡片
          if (mounted) {
            final prov = context.read<MemeProvider>();
            if (!prov.isMulti) prov.toggleMulti();
            prov.toggleSelect(widget.meme.id);
          }
          break;
        case 'delete': _confirmDelete(); break;
      }
    });
  }

  void _showRenameDialog() async {
    final l10n = context.read<LocaleProvider>().l10n;
    final ctrl = TextEditingController(text: widget.meme.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('rename_title')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.tr('new_name_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      if (mounted) context.read<MemeProvider>().renameMeme(widget.meme.id, newName);
    }
  }

  void _showTypeDialog() {
    final l10n = context.read<LocaleProvider>().l10n;
    final settings = context.read<SettingsProvider>();
    final allTypes = [
      {'type': Meme.typeEmoji, 'label': l10n.tr('type_emoji'), 'icon': Icons.emoji_emotions_outlined},
      {'type': Meme.typeGif, 'label': l10n.tr('type_gif'), 'icon': Icons.animation},
      {'type': Meme.typeImage, 'label': l10n.tr('type_image'), 'icon': Icons.image_outlined},
      {'type': Meme.typeText, 'label': l10n.tr('type_text'), 'icon': Icons.text_fields},
      {'type': Meme.typePortrait, 'label': l10n.tr('type_portrait'), 'icon': Icons.accessibility_new},
      {'type': Meme.typeCg, 'label': l10n.tr('type_cg'), 'icon': Icons.wallpaper_outlined},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('type_character_card'), 'icon': Icons.contact_page_outlined},
      {'type': Meme.typeVector, 'label': l10n.tr('type_vector'), 'icon': Icons.polyline_outlined},
      {'type': Meme.typePsd, 'label': l10n.tr('type_psd'), 'icon': Icons.layers_outlined},
      {'type': Meme.typeManga, 'label': l10n.tr('type_manga'), 'icon': Icons.menu_book_outlined},
      {'type': Meme.typeSpriteSheet, 'label': l10n.tr('type_sprite_sheet'), 'icon': Icons.view_carousel},
      {'type': Meme.typeFile, 'label': l10n.tr('type_file'), 'icon': Icons.folder_outlined},
    ];
    // 仅显示已启用的分类 + 当前 meme 所属分类（即便被隐藏也可保持）
    final types = allTypes.where((t) {
      final type = t['type'] as String;
      return settings.isCategoryVisible(type) || widget.meme.type == type;
    }).toList();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('select_category')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: types.map((t) {
            final type = t['type'] as String;
            final label = t['label'] as String;
            final icon = t['icon'] as IconData;
            // 同分类下的旧类型也视为选中（pdf→file, novel/md→text）
            final selected = widget.meme.type == type ||
                (type == Meme.typeFile && widget.meme.type == Meme.typePdf) ||
                (type == Meme.typeText &&
                    (widget.meme.type == Meme.typeMd ||
                     widget.meme.type == Meme.typeNovel));
            return ListTile(
              leading: Icon(icon, color: selected ? Theme.of(dCtx).colorScheme.primary : null),
              title: Text(label),
              trailing: selected ? Icon(Icons.check, color: Theme.of(dCtx).colorScheme.primary) : null,
              onTap: () async {
                if (mounted) {
                  context.read<MemeProvider>().setMemeType(widget.meme.id, type);
                }
                Navigator.pop(dCtx);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
        ],
      ),
    );
  }

  void _confirmDelete() async {
    final l10n = context.read<LocaleProvider>().l10n;
    final prov = context.read<MemeProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('delete_meme_title')),
        content: Text(l10n.tr('delete_confirm', args: {'name': widget.meme.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(l10n.tr('delete'))),
        ],
      ),
    );
    if (confirm == true) {
      await prov.deleteMeme(widget.meme.id);
    }
  }

  String _typeLabel(String type) {
    final l10n = context.read<LocaleProvider>().l10n;
    // Meme.typeLabelKey 是实例 getter，此处用 widget.meme 的类型
    return type == widget.meme.type
        ? l10n.tr(widget.meme.typeLabelKey)
        : l10n.tr('type_image');
  }

  void _reimport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: Meme.supportedExtensions,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      final file = result.files.first;
      final storage = context.read<StorageService>();
      // 用新文件覆盖旧字节
      await storage.reimportMeme(widget.meme.id, file);
      if (mounted) {
        setState(() {
          _bytes = file.bytes;
          _file = (!kIsWeb && file.path != null) ? File(file.path!) : null;
          _loading = false;
        });
        if (file.bytes != null) {
          _loadAspectRatioFromBytes(file.bytes!);
        } else if (_file != null) {
          _loadAspectRatioFromFile();
        }
      }
    }
  }
}
