import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/repositories/sticker_repository.dart';
import '../providers/sticker_providers.dart';
import '../widgets/sticker_search_delegate.dart';
import 'pack_detail_screen.dart';

/// 创建/编辑表情包对话框
class _PackEditDialog extends ConsumerStatefulWidget {
  final String? packId; // null = 新建
  const _PackEditDialog({this.packId});

  @override
  ConsumerState<_PackEditDialog> createState() => _PackEditDialogState();
}

class _PackEditDialogState extends ConsumerState<_PackEditDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.packId != null) {
      final repo = ref.read(stickerRepositoryProvider);
      repo.getPack(widget.packId!).then((pack) {
        if (pack != null && mounted) {
          _nameCtrl.text = pack.name;
          _descCtrl.text = pack.description ?? '';
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.packId != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑表情包' : '新建表情包'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '给你的表情包取个名字',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: '描述（可选）',
              hintText: '简单描述一下这个表情包',
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final repo = ref.read(stickerRepositoryProvider);
            if (isEdit) {
              await repo.updatePack(
                widget.packId!,
                name: name,
                description:
                    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              );
            } else {
              await repo.createPack(
                name: name,
                description:
                    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              );
            }
            if (mounted) Navigator.of(context).pop();
          },
          child: Text(isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(allPacksProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mako Meme'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: StickerSearchDelegate(ref),
              );
            },
          ),
        ],
      ),
      body: packsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text('加载失败: $e'),
            ],
          ),
        ),
        data: (packs) {
          if (packs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_emotions_outlined,
                      size: 80,
                      color: theme.colorScheme.primary.withAlpha(100)),
                  const SizedBox(height: 16),
                  Text(
                    '还没有表情包',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击下方按钮创建第一个表情包吧',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(100),
                    ),
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridColumns(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: packs.length,
              itemBuilder: (context, index) {
                final pack = packs[index];
                return _PackCard(pack: pack);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const _PackEditDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('新建表情包'),
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
}

class _PackCard extends ConsumerWidget {
  final StickerPackData pack;
  const _PackCard({required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stickersAsync = ref.watch(stickersByPackProvider(pack.id));

    return Card(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PackDetailScreen(packId: pack.id, packName: pack.name),
            ),
          );
        },
        onLongPress: () => _showPackMenu(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: stickersAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, __) =>
                      Icon(Icons.broken_image, color: theme.colorScheme.error),
                  data: (stickers) {
                    if (stickers.isEmpty) {
                      return Icon(Icons.emoji_emotions_outlined,
                          size: 48,
                          color: theme.colorScheme.primary.withAlpha(100));
                    }
                    return _ThumbnailGrid(
                      stickers: stickers.take(4).toList(),
                      repo: ref.read(stickerRepositoryProvider),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              if (pack.description != null && pack.description!.isNotEmpty)
                Text(
                  pack.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPackMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => _PackEditDialog(packId: pack.id),
                );
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
                    content: Text('确定要删除「${pack.name}」及其所有表情吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final repo = ref.read(stickerRepositoryProvider);
                  await repo.deletePack(pack.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 2x2 缩略图网格
class _ThumbnailGrid extends StatelessWidget {
  final List<StickerData> stickers;
  final StickerRepository repo;
  const _ThumbnailGrid({required this.stickers, required this.repo});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      physics: const NeverScrollableScrollPhysics(),
      children: stickers.map((s) {
        return FutureBuilder<String>(
          future: repo.stickerFullPath(s.storedPath),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(snapshot.data!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.error),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}
