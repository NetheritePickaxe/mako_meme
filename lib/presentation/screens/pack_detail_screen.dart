import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../data/database/database.dart';
import '../providers/sticker_providers.dart';
import '../widgets/sticker_preview.dart';

class PackDetailScreen extends ConsumerStatefulWidget {
  final String packId;
  final String packName;

  const PackDetailScreen({
    super.key,
    required this.packId,
    required this.packName,
  });

  @override
  ConsumerState<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends ConsumerState<PackDetailScreen> {
  bool _batchMode = false;
  final Set<String> _selectedIds = {};
  List<StickerData> _allStickers = [];

  void _toggleBatchMode() {
    setState(() {
      _batchMode = !_batchMode;
      if (!_batchMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(String stickerId) {
    setState(() {
      if (_selectedIds.contains(stickerId)) {
        _selectedIds.remove(stickerId);
      } else {
        _selectedIds.add(stickerId);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个表情吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final repo = ref.read(stickerRepositoryProvider);
      for (final id in _selectedIds.toList()) {
        await repo.deleteSticker(id);
      }
      setState(() {
        _selectedIds.clear();
        _batchMode = false;
      });
    }
  }

  Future<void> _shareSelected() async {
    if (_selectedIds.isEmpty) return;
    final repo = ref.read(stickerRepositoryProvider);
    final files = <XFile>[];
    for (final id in _selectedIds) {
      final sticker = _allStickers.firstWhere((s) => s.id == id);
      final path = await repo.stickerFullPath(sticker.storedPath);
      files.add(XFile(path));
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files);
    }
  }

  void _editTagsSelected() async {
    if (_selectedIds.isEmpty) return;
    final controller = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量添加标签 (${_selectedIds.length} 个)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入标签，用逗号分隔（会追加到已有标签）',
            labelText: '新标签',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final tags = controller.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              Navigator.pop(ctx, tags);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final repo = ref.read(stickerRepositoryProvider);
      for (final id in _selectedIds) {
        final sticker = _allStickers.firstWhere((s) => s.id == id);
        final existingTags =
            sticker.tags?.split(',').map((t) => t.trim()).toList() ?? [];
        final merged = {...existingTags, ...result}.toList();
        await repo.updateStickerTags(id, merged);
      }
      setState(() {
        _selectedIds.clear();
        _batchMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stickersAsync = ref.watch(stickersByPackProvider(widget.packId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.packName),
        actions: [
          if (_batchMode) ...[
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: '批量标签',
              onPressed:
                  _selectedIds.isEmpty ? null : _editTagsSelected,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '批量分享',
              onPressed: _selectedIds.isEmpty ? null : _shareSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: '批量删除',
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            ),
            Text('${_selectedIds.length}'),
          ],
          IconButton(
            icon: Icon(_batchMode ? Icons.close : Icons.checklist),
            tooltip: _batchMode ? '退出选择' : '批量选择',
            onPressed: stickersAsync.hasValue && stickersAsync.value!.isNotEmpty
                ? _toggleBatchMode
                : null,
          ),
        ],
      ),
      body: DropTarget(
        onDragDone: (detail) async {
          final paths = detail.files
              .where((f) {
                final ext = f.path.split('.').last.toLowerCase();
                return ['png', 'gif', 'webp', 'jpg', 'jpeg'].contains(ext);
              })
              .map((f) => f.path)
              .toList();
          if (paths.isEmpty) return;
          final repo = ref.read(stickerRepositoryProvider);
          await repo.importStickers(packId: widget.packId, sourcePaths: paths);
        },
        onDragEntered: (_) {},
        child: stickersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (stickers) {
          _allStickers = stickers;
          if (stickers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined,
                      size: 64,
                      color: theme.colorScheme.primary.withAlpha(100)),
                  const SizedBox(height: 16),
                  Text('这个表情包还是空的',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('点击右下角按钮导入表情',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      )),
                ],
              ),
            );
          }
          return MasonryGridView.count(
            crossAxisCount: _gridColumns(context),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            padding: const EdgeInsets.all(8),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final sticker = stickers[index];
              final isSelected = _selectedIds.contains(sticker.id);
              return _StickerTile(
                sticker: sticker,
                selected: isSelected,
                batchMode: _batchMode,
                onTap: () {
                  if (_batchMode) {
                    _toggleSelection(sticker.id);
                  } else {
                    _showPreview(context, sticker);
                  }
                },
                onLongPress: () {
                  if (!_batchMode) {
                    _showStickerMenu(context, sticker);
                  }
                },
              );
            },
          );
        },
      ),
      ),
      floatingActionButton: _batchMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _importStickers(context),
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('导入表情'),
            ),
    );
  }

  int _gridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    return 3;
  }

  Future<void> _importStickers(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'gif', 'webp', 'jpg', 'jpeg'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final repo = ref.read(stickerRepositoryProvider);
    final paths =
        result.files.where((f) => f.path != null).map((f) => f.path!).toList();

    if (paths.isEmpty) return;

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    await repo.importStickers(packId: widget.packId, sourcePaths: paths);

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showPreview(BuildContext context, StickerData sticker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StickerPreviewScreen(sticker: sticker),
      ),
    );
  }

  void _showStickerMenu(BuildContext context, StickerData sticker) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享'),
              onTap: () async {
                Navigator.pop(ctx);
                final repo = ref.read(stickerRepositoryProvider);
                final path = await repo.stickerFullPath(sticker.storedPath);
                await Share.shareXFiles([XFile(path)]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑标签'),
              onTap: () {
                Navigator.pop(ctx);
                _editTags(context, sticker);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('确认删除'),
                    content: const Text('确定要删除这个表情吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final repo = ref.read(stickerRepositoryProvider);
                  await repo.deleteSticker(sticker.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editTags(BuildContext context, StickerData sticker) async {
    final controller =
        TextEditingController(text: sticker.tags?.replaceAll(',', ', ') ?? '');
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入标签，用逗号分隔',
            labelText: '标签',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final tags = controller.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              Navigator.pop(ctx, tags);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      final repo = ref.read(stickerRepositoryProvider);
      await repo.updateStickerTags(sticker.id, result);
    }
  }
}

class _StickerTile extends ConsumerWidget {
  final StickerData sticker;
  final bool selected;
  final bool batchMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StickerTile({
    required this.sticker,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.batchMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(stickerRepositoryProvider);
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: FutureBuilder<String>(
              future: repo.stickerFullPath(sticker.storedPath),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(height: 120);
                }
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image),
                  ),
                );
              },
            ),
          ),
          if (selected)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              ),
            ),
          if (batchMode && !selected)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(180),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
