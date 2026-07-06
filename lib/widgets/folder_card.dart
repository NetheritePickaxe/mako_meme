import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/folder.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../services/storage_service.dart';

/// 文件夹卡片 — 也是一个拖放目标，接收表情包拖入
class FolderCard extends StatelessWidget {
  final MemeFolder folder;
  final int count;
  final bool isActive;

  const FolderCard({
    super.key,
    required this.folder,
    required this.count,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(folder.colorValue);

    return DragTarget<Meme>(
      onAcceptWithDetails: (details) {
        final prov = context.read<MemeProvider>();
        prov.moveToFolder(details.data.id, folder.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移至「${folder.name}」'), duration: const Duration(seconds: 1)),
        );
      },
      builder: (ctx, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () {
            final prov = context.read<MemeProvider>();
            prov.selectFolder(folder.id);
            prov.clearMood();
          },
          onSecondaryTapUp: (details) {
            _showFolderContextMenu(details.globalPosition, context, folder, count);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDragOver
                  ? color.withValues(alpha: 0.2)
                  : isActive
                      ? color.withValues(alpha: 0.15)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: Border.all(
                color: isDragOver
                    ? color
                    : isActive
                        ? color.withValues(alpha: 0.6)
                        : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder, size: 48, color: isActive ? Theme.of(context).colorScheme.tertiary : color),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count 个表情',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                _CoverThumbnail(
                  folder: folder,
                  count: count,
                  theme: theme,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFolderContextMenu(Offset globalPos, BuildContext context, MemeFolder folder, int count) {
    if (count == 0) return;
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(globalPos);
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
        Offset.zero & renderBox.size,
      ),
      items: <PopupMenuEntry>[
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'set_cover',
          child: ListTile(leading: Icon(Icons.photo_library), title: Text('设置封面'), dense: true),
        ),
        PopupMenuItem<String>(
          value: 'clear_cover',
          enabled: folder.coverMemeId != null,
          child: ListTile(leading: Icon(Icons.clear), title: const Text('清除封面'), dense: true),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      if (value == 'set_cover') {
        _showCoverSelector(context, folder);
      } else if (value == 'clear_cover') {
        final storage = context.read<StorageService>();
        storage.updateFolderCover(folder.id, null);
      }
    });
  }

  void _showCoverSelector(BuildContext context, MemeFolder folder) {
    final prov = context.read<MemeProvider>();
    final memes = prov.memesInFolder(folder.id);
    if (memes.isEmpty) return;

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('设置封面'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: memes.length,
            itemBuilder: (ctx, i) {
              final meme = memes[i];
              return FutureBuilder<Uint8List?>(
                future: context.read<StorageService>().readMemeBytes(meme.filePath),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade200,
                      ),
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  final isSelected = meme.id == folder.coverMemeId;
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final storage = context.read<StorageService>();
              storage.updateFolderCover(folder.id, null);
              Navigator.pop(dCtx);
            },
            child: const Text('自动'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('取消'),
          ),
        ],
      ),
    ).then((_) {
      // Dialog dismissed, nothing to do
    });
  }
}

class _CoverThumbnail extends StatelessWidget {
  final MemeFolder folder;
  final int count;
  final ThemeData theme;

  const _CoverThumbnail({
    required this.folder,
    required this.count,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    final prov = context.read<MemeProvider>();
    final memeId = folder.coverMemeId ?? prov.memesInFolder(folder.id).firstOrNull?.id;

    if (memeId == null) return const SizedBox.shrink();

    return FutureBuilder<Uint8List?>(
      future: context.read<StorageService>().readMemeBytes(
        prov.memes.firstWhere((m) => m.id == memeId).filePath,
      ),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        return Positioned(
          bottom: 8,
          right: 8,
          child: ClipOval(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Image.memory(
                snapshot.data!,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }
}
