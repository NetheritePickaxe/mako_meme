import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../services/storage_service.dart';
import 'character_card_editor_screen.dart';

/// 是否为移动平台
bool _isMobilePlatform() {
  if (kIsWeb) return false;
  final p = defaultTargetPlatform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

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
  final Map<int, File?> _fileCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
  }

  Meme get _meme => widget.memes[_currentIndex];

  Future<void> _ensureBytes(int index) async {
    if (_bytesCache.containsKey(index) || _fileCache.containsKey(index)) return;
    final m = widget.memes[index];
    if (!m.isImageType || m.filePath.isEmpty) {
      _bytesCache[index] = null;
      return;
    }
    try {
      final storage = context.read<StorageService>();
      if (kIsWeb) {
        final b = await storage.readMemeBytes(m.filePath);
        if (mounted) setState(() => _bytesCache[index] = b);
      } else {
        // 原生端：直接拿 File，不读字节，避免大文件 OOM
        final f = storage.getMemeFile(m.filePath);
        final exists = f != null && await f.exists();
        if (mounted) setState(() => _fileCache[index] = exists ? f : null);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<MemeProvider>();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _meme.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_currentIndex + 1} / ${widget.memes.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        physics: const BouncingScrollPhysics(),
        controller: _controller,
        itemCount: widget.memes.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) {
          final m = widget.memes[i];
          return Column(
            children: [
              Expanded(child: _buildImageArea(m, i)),
              _buildDraggableDetailPanel(theme, prov, m),
            ],
          );
        },
      ),
    );
  }

  /// 图片展示区：图片用 PhotoView 缩放，GIF 用 Image.memory，文字居中显示
  Widget _buildImageArea(Meme m, int i) {
    final theme = Theme.of(context);
    _ensureBytes(i);
    final bytes = _bytesCache[i];
    final file = _fileCache[i];
    final hasData = bytes != null || file != null;

    if (m.isImageType) {
      if (!hasData) {
        return Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        );
      }
      if (m.type == Meme.typeGif) {
        return Center(
          child: InteractiveViewer(
            child: file != null
                ? Image.file(file, fit: BoxFit.contain)
                : Image.memory(bytes!, fit: BoxFit.contain),
          ),
        );
      }
      return PhotoView(
        imageProvider: file != null
            ? FileImage(file)
            : MemoryImage(bytes!),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        heroAttributes: PhotoViewHeroAttributes(tag: m.id),
        backgroundDecoration: BoxDecoration(color: theme.colorScheme.surface),
        loadingBuilder: (_, event) => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
            value: event == null ? null : event.cumulativeBytesLoaded /
                (event.expectedTotalBytes ?? 1),
          ),
        ),
      );
    }

    // 文字表情居中显示
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          m.textContent ?? '',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 底部详情面板：可拖动展开/收起
  Widget _buildDraggableDetailPanel(ThemeData theme, MemeProvider prov, Meme m) {
    final isMobile = _isMobilePlatform();
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.85,
      builder: (ctx, controller) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 手势指示条（可拖动）
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 名称（点击可编辑）
                GestureDetector(
                  onTap: _rename,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.edit,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 文件信息
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _infoChip(theme, _typeLabel(m.type), icon: _typeIcon(m.type)),
                    _infoChip(theme, _formatFileSize(m.fileSize), icon: Icons.data_usage),
                    _infoChip(theme, _formatDate(m.createdAt), icon: Icons.access_time),
                  ],
                ),
                if (m.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: m.tags
                        .map((t) => Chip(
                              label: Text(t, style: const TextStyle(fontSize: 11)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                // 操作按钮（移动端图片不显示复制）
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (!(isMobile && m.isImageType))
                      _actionButton(theme, '复制', Icons.copy, _copy),
                    _actionButton(theme, '分享', Icons.ios_share, _share),
                    _actionButton(
                      theme,
                      m.isFavorite ? '已收藏' : '收藏',
                      m.isFavorite ? Icons.favorite : Icons.favorite_border,
                      () => prov.toggleFavorite(m.id),
                      color: m.isFavorite ? Colors.red : null,
                    ),
                    _actionButton(theme, '分类', Icons.label_outline, _showTypeDialog),
                    _actionButton(theme, '重命名', Icons.edit, _rename),
                    _actionButton(theme, '删除', Icons.delete_outline, _confirmDelete, color: Colors.red),
                  ],
                ),
                if (m.type == Meme.typeCharacterCard) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _editCharacterCard,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('编辑角色卡'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoChip(ThemeData theme, String text, {IconData? icon}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    ThemeData theme,
    String label,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: c, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case Meme.typeEmoji:
        return '表情';
      case Meme.typeGif:
        return 'GIF';
      case Meme.typeText:
        return '文字';
      case Meme.typePortrait:
        return '立绘';
      case Meme.typeCg:
        return 'CG';
      case Meme.typeCharacterCard:
        return '角色卡';
      default:
        return '图片';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case Meme.typeEmoji:
        return Icons.face;
      case Meme.typeGif:
        return Icons.gif;
      case Meme.typeText:
        return Icons.text_fields;
      case Meme.typePortrait:
        return Icons.portrait;
      case Meme.typeCg:
        return Icons.photo_library;
      case Meme.typeCharacterCard:
        return Icons.person_outline;
      default:
        return Icons.image;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _copy() {
    final m = _meme;
    // 文字类型：复制文字内容到剪贴板
    if (m.type == Meme.typeText) {
      final text = m.textContent ?? '';
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无文字内容'), duration: Duration(seconds: 1)),
        );
        return;
      }
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制文字到剪贴板'), duration: Duration(seconds: 1)),
      );
      return;
    }
    // 表情类型：复制表情符号
    if (m.type == Meme.typeEmoji) {
      final text = m.textContent ?? m.name;
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
      return;
    }
    // 图片类型：复制文件名（Flutter 无原生图片剪贴板支持）
    Clipboard.setData(ClipboardData(text: m.name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制名称: ${m.name}'), duration: const Duration(seconds: 1)),
    );
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

  void _editCharacterCard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CharacterCardEditorScreen(meme: _meme),
      ),
    );
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
