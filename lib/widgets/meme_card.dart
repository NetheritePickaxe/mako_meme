import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../services/storage_service.dart';
import '../screens/meme_viewer_screen.dart';

class MemeCard extends StatefulWidget {
  final Meme meme;
  final void Function(Meme dragged, Meme target)? onReorder;

  const MemeCard({super.key, required this.meme, this.onReorder});

  @override
  State<MemeCard> createState() => _MemeCardState();
}

class _MemeCardState extends State<MemeCard> {
  Uint8List? _bytes;       // Web 端使用
  File? _file;             // 原生端使用
  bool _loading = true;
  double _aspectRatio = 1.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBytes();
  }

  void _loadBytes() {
    if (!_loading) return;
    final storage = context.read<StorageService>();
    if (widget.meme.isImageType && widget.meme.filePath.isNotEmpty) {
      if (kIsWeb) {
        // Web：读 bytes
        storage.readMemeBytes(widget.meme.filePath).then((b) {
          if (mounted) {
            setState(() {
              _bytes = b;
              _loading = false;
            });
            if (b != null) _loadAspectRatioFromBytes(b);
          }
        }, onError: (_) {
          if (mounted) setState(() { _loading = false; });
        });
      } else {
        // 原生：用 File 直接显示，避免一次性载入大文件字节
        final f = storage.getMemeFile(widget.meme.filePath);
        if (f == null) {
          if (mounted) setState(() { _loading = false; });
          return;
        }
        f.exists().then((exists) {
          if (mounted) {
            setState(() {
              _file = exists ? f : null;
              _loading = false;
            });
            if (exists) _loadAspectRatioFromFile();
          }
        }, onError: (_) {
          if (mounted) setState(() { _loading = false; });
        });
      }
    } else {
      _loading = false;
    }
  }

  Future<void> _loadAspectRatioFromBytes(Uint8List bytes) async {
    // Web 上仍用 codec 解码，Web 文件通常不大
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      if (mounted && w > 0 && h > 0) {
        setState(() => _aspectRatio = w / h);
      }
    } catch (_) {}
  }

  Future<void> _loadAspectRatioFromFile() async {
    // 原生端只读 64KB 头部解析宽高，不解码整图
    try {
      final storage = context.read<StorageService>();
      final ratio = await storage.getImageAspectRatio(widget.meme.filePath);
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
      widget.meme.type == Meme.typeEmoji || widget.meme.type == Meme.typeText;

  double get _effectiveAspectRatio {
    if (_isSquare) return 1.0;
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
      return LongPressDraggable<Meme>(
        data: widget.meme,
        feedback: _buildFeedback(),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildAspectRatioCard(prov, isSelected, isMulti, theme),
        ),
        child: GestureDetector(
          onTap: isMulti ? () => prov.toggleSelect(widget.meme.id) : _copyToClipboard,
          onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
          child: _buildInner(prov, isSelected, isMulti, theme),
        ),
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
        child: GestureDetector(
          onTap: () => prov.toggleSelect(widget.meme.id),
          child: inner,
        ),
      );
    }

    // 移动端普通模式：点击预览，长按分享
    return GestureDetector(
      onTap: isMulti ? () => prov.toggleSelect(widget.meme.id) : _openViewer,
      onLongPress: isMulti ? null : _shareMeme,
      child: _buildInner(prov, isSelected, isMulti, theme),
    );
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

  /// 方形卡片（表情/文字）固定 1:1，图片卡片按真实宽高比
  Widget _buildAspectRatioCard(MemeProvider prov, bool isSelected, bool isMulti, ThemeData theme) {
    return AspectRatio(
      aspectRatio: _effectiveAspectRatio,
      child: _buildCard(context, prov, isSelected, isMulti, theme),
    );
  }

  Widget _buildFeedback() {
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

  /// 统一的缩略图渲染：原生端用 Image.file（不读字节），Web 端用 Image.memory
  Widget _buildThumbnail({required BoxFit fit}) {
    if (_file != null) {
      return Image.file(
        _file!,
        fit: fit,
        // 限制缓存尺寸，避免超大图片全分辨率缓存
        cacheWidth: 512,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: fit, errorBuilder: (_, _, _) => _placeholder());
    }
    return Container(color: Colors.grey.shade300);
  }

  Widget _buildCard(BuildContext context, MemeProvider prov, bool isSelected, bool isMulti, ThemeData theme) {
    return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.meme.isImageType && _loading)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else if (widget.meme.isImageType && (_file != null || _bytes != null))
                _buildThumbnail(fit: BoxFit.cover)
              else if (widget.meme.isImageType)
                // 图片丢失（Web 刷新后或文件不存在）
                Container(
                  color: Colors.grey.shade200,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 24, color: Colors.grey.shade500),
                        const SizedBox(height: 4),
                        Text('丢失', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
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
                      fontWeight: widget.meme.type == Meme.typeText ? FontWeight.w500 : FontWeight.normal,
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
              if (widget.meme.type != Meme.typeImage)
                Positioned(bottom: 6, left: 6,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                    child: Text(_typeLabel(widget.meme.type),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  void _copyToClipboard() {
    final hasData = _bytes != null || _file != null;
    if (widget.meme.isImageType && !hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片丢失，无法复制'), duration: Duration(seconds: 1)),
      );
      return;
    }
    // Flutter 无原生图片剪贴板支持（需 platform channel），此处简化处理
    Clipboard.setData(ClipboardData(text: widget.meme.name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制: ${widget.meme.name}'), duration: const Duration(seconds: 1)),
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

  void _shareMeme() {
    Share.share(widget.meme.name);
  }

  void _showContextMenu(Offset tapPosition) {
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(1, 1),
        Offset.zero & MediaQuery.of(context).size,
      ),
      items: <PopupMenuEntry<String>>[
        if (_bytes == null && _file == null && !_loading)
          const PopupMenuItem<String>(
            value: 'reimport',
            child: ListTile(leading: Icon(Icons.refresh), title: Text('重新导入'), dense: true),
          ),
        if (_bytes != null || _file != null)
          const PopupMenuItem<String>(
            value: 'preview',
            child: ListTile(leading: Icon(Icons.zoom_in), title: Text('预览大图'), dense: true),
          ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(leading: Icon(Icons.edit), title: Text('重命名'), dense: true),
        ),
        const PopupMenuItem<String>(
          value: 'type',
          child: ListTile(leading: Icon(Icons.label_outline), title: Text('修改分类'), dense: true),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: ListTile(leading: Icon(Icons.copy), title: Text('复制'), dense: true),
        ),
        const PopupMenuItem<String>(
          value: 'share',
          child: ListTile(leading: Icon(Icons.share), title: Text('分享'), dense: true),
        ),
        PopupMenuItem<String>(
          value: 'favorite',
          child: ListTile(
            leading: Icon(Icons.favorite, color: widget.meme.isFavorite ? Colors.red : null),
            title: Text(widget.meme.isFavorite ? '取消收藏' : '收藏'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('删除', style: TextStyle(color: Colors.red)), dense: true),
        ),
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
        case 'delete': _confirmDelete(); break;
      }
    });
  }

  void _showRenameDialog() async {
    final ctrl = TextEditingController(text: widget.meme.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      if (mounted) context.read<MemeProvider>().renameMeme(widget.meme.id, newName);
    }
  }

  void _showTypeDialog() {
    final types = [
      {'type': Meme.typeEmoji, 'label': '表情', 'icon': Icons.face},
      {'type': Meme.typeGif, 'label': 'GIF', 'icon': Icons.gif},
      {'type': Meme.typeImage, 'label': '图片', 'icon': Icons.image},
      {'type': Meme.typeText, 'label': '文字', 'icon': Icons.text_fields},
      {'type': Meme.typePortrait, 'label': '立绘', 'icon': Icons.portrait},
      {'type': Meme.typeCg, 'label': 'CG', 'icon': Icons.photo_library},
      {'type': Meme.typeCharacterCard, 'label': '角色卡', 'icon': Icons.person_outline},
    ];

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('选择分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: types.map((t) {
            final type = t['type'] as String;
            final label = t['label'] as String;
            final icon = t['icon'] as IconData;
            final selected = widget.meme.type == type;
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
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
        ],
      ),
    );
  }

  void _confirmDelete() async {
    final prov = context.read<MemeProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('删除表情'),
        content: Text('确定删除「${widget.meme.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await prov.deleteMeme(widget.meme.id);
    }
  }

  Widget _placeholder() => Container(
    color: Colors.grey.shade200,
    child: Icon(Icons.broken_image, color: Colors.grey.shade400),
  );

  String _typeLabel(String type) {
    switch (type) {
      case Meme.typeEmoji: return '表情';
      case Meme.typeGif: return 'GIF';
      case Meme.typeText: return '文字';
      case Meme.typePortrait: return '立绘';
      case Meme.typeCg: return 'CG';
      case Meme.typeCharacterCard: return '角色卡';
      default: return '';
    }
  }

  void _reimport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
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
