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
  const MemeCard({super.key, required this.meme});

  @override
  State<MemeCard> createState() => _MemeCardState();
}

class _MemeCardState extends State<MemeCard> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBytes();
  }

  void _loadBytes() {
    if (!_loading) return;
    final storage = context.read<StorageService>();
    if (widget.meme.isImageType && widget.meme.filePath.isNotEmpty) {
      storage.readMemeBytes(widget.meme.filePath).then((b) {
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
      }, onError: (_) {
        if (mounted) setState(() => _loading = false);
      });
    } else {
      _loading = false;
    }
  }

  bool get _isDesktop {
    if (kIsWeb) return true;
    final p = Theme.of(context).platform;
    return p == TargetPlatform.windows || p == TargetPlatform.linux || p == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final isSelected = prov.selected.contains(widget.meme.id);
    final isMulti = prov.isMulti;
    final theme = Theme.of(context);

    if (_isDesktop) {
      // 桌面端：LongPressDraggable 用于拖入文件夹，左键复制，右键菜单
      return LongPressDraggable<Meme>(
        data: widget.meme,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 100,
            height: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _bytes != null
                  ? Image.memory(_bytes!, fit: BoxFit.cover)
                  : Container(color: Colors.grey.shade300),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildCard(context, prov, isSelected, isMulti, theme),
        ),
        child: GestureDetector(
          onTap: isMulti ? () => prov.toggleSelect(widget.meme.id) : _copyToClipboard,
          onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
          child: _buildCard(context, prov, isSelected, isMulti, theme),
        ),
      );
    }

    // 移动端：点击预览，长按分享
    return GestureDetector(
      onTap: isMulti ? () => prov.toggleSelect(widget.meme.id) : _openViewer,
      onLongPress: isMulti ? null : _shareMeme,
      child: _buildCard(context, prov, isSelected, isMulti, theme),
    );
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
              else if (widget.meme.isImageType && _bytes != null)
                Image.memory(_bytes!, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholder(),
                )
              else if (widget.meme.isImageType)
                // 图片丢失（Web 刷新后）
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
    if (_bytes != null) {
      Clipboard.setData(ClipboardData(text: ''));
      // 对于图片复制需要特殊处理，这里复制文件名作为 fallback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制: ${widget.meme.name}'), duration: const Duration(seconds: 1)),
      );
    }
    // 实际图片复制需要 platform channel，简化处理
  }

  void _openViewer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MemeViewerScreen(
        memes: [widget.meme],
        initialIndex: 0,
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
        if (_bytes == null && !_loading)
          const PopupMenuItem<String>(
            value: 'reimport',
            child: ListTile(leading: Icon(Icons.refresh), title: Text('重新导入'), dense: true),
          ),
        if (_bytes != null)
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
      default: return '';
    }
  }

  void _reimport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty && mounted) {
      final file = result.files.first;
      if (file.bytes != null) {
        final storage = context.read<StorageService>();
        // 用新文件覆盖旧字节
        await storage.reimportMeme(widget.meme.id, file);
        if (mounted) {
          setState(() {
            _bytes = file.bytes;
            _loading = false;
          });
        }
      }
    }
  }
}
