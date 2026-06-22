import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/folder.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';

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
                Icon(Icons.folder, size: 36, color: color),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
