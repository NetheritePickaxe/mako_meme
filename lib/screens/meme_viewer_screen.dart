import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../services/storage_service.dart';

class MemeViewerScreen extends StatefulWidget {
  final List<Meme> memes;
  final int initialIndex;
  const MemeViewerScreen({super.key, required this.memes, required this.initialIndex});

  @override
  State<MemeViewerScreen> createState() => _MemeViewerScreenState();
}

class _MemeViewerScreenState extends State<MemeViewerScreen> {
  late PageController _controller;
  late int _currentIndex;
  final Map<int, Uint8List?> _bytesCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
  }

  Meme get _meme => widget.memes[_currentIndex];

  Future<void> _ensureBytes(int index) async {
    if (_bytesCache.containsKey(index)) return;
    final m = widget.memes[index];
    if (!m.isImageType || m.filePath.isEmpty) {
      _bytesCache[index] = null;
      return;
    }
    try {
      final storage = context.read<StorageService>();
      final b = await storage.readMemeBytes(m.filePath);
      if (mounted) setState(() => _bytesCache[index] = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(_meme.name, style: const TextStyle(fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 复制
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制',
            onPressed: _copy,
          ),
          // 分享
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '分享',
            onPressed: _share,
          ),
          // 收藏
          IconButton(
            icon: Icon(_meme.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _meme.isFavorite ? Colors.red : Colors.white),
            onPressed: () => prov.toggleFavorite(_meme.id),
          ),
          // 更多
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'rename') {
                _rename();
              } else if (v == 'type') {
                _showTypeDialog();
              } else if (v == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: ListTile(
                leading: Icon(Icons.edit), title: Text('重命名'), dense: true)),
              const PopupMenuItem(value: 'type', child: ListTile(
                leading: Icon(Icons.label_outline), title: Text('修改分类'), dense: true)),
              const PopupMenuItem(value: 'delete', child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('删除', style: TextStyle(color: Colors.red)), dense: true)),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => _toggleUI(),
        child: Stack(
          children: [
            PageView.builder(
              physics: const BouncingScrollPhysics(),
              itemBuilder: (ctx, i) {
                _ensureBytes(i);
                final m = widget.memes[i];
                final bytes = _bytesCache[i];
                if (bytes == null) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
                }
                if (m.isImageType) {
                  // GIF 用普通 Image.memory（支持动画），非 GIF 用 PhotoView（支持缩放）
                  if (m.type == Meme.typeGif) {
                    return Center(
                      child: InteractiveViewer(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    );
                  }
                  return PhotoView(
                    imageProvider: MemoryImage(bytes),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                    heroAttributes: PhotoViewHeroAttributes(tag: m.id),
                    backgroundDecoration: const BoxDecoration(color: Colors.black),
                  );
                }
                return Center(
                  child: Text(
                    m.textContent ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 48),
                    textAlign: TextAlign.center,
                  ),
                );
              },
              itemCount: widget.memes.length,
              controller: _controller,
              onPageChanged: (i) => setState(() => _currentIndex = i),
            ),
            // 底部页码
            Positioned(
              bottom: 20, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.memes.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _uiVisible = true;
  void _toggleUI() {
    setState(() => _uiVisible = !_uiVisible);
  }

  void _copy() {
    final bytes = _bytesCache[_currentIndex];
    if (bytes != null) {
      Clipboard.setData(ClipboardData(text: ''));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _share() {
    Share.share(_meme.name);
  }

  void _rename() async {
    final ctrl = TextEditingController(text: _meme.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      if (mounted) context.read<MemeProvider>().renameMeme(_meme.id, newName);
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
            final selected = _meme.type == type;
            return ListTile(
              leading: Icon(icon, color: selected ? Theme.of(dCtx).colorScheme.primary : null),
              title: Text(label),
              trailing: selected ? Icon(Icons.check, color: Theme.of(dCtx).colorScheme.primary) : null,
              onTap: () async {
                if (mounted) {
                  context.read<MemeProvider>().setMemeType(_meme.id, type);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('删除表情'),
        content: Text('确定删除「${_meme.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      if (mounted) {
        final prov = context.read<MemeProvider>();
        await prov.deleteMeme(_meme.id);
        if (mounted) Navigator.pop(context);
      }
    }
  }
}
