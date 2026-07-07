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
    final prov = context.watch<MemeProvider>();
    final isMulti = prov.isMulti;
    final isFolderSelected = prov.selectedFolders.contains(folder.id);

    // 多选模式：点击切换选中，显示复选框，禁用拖放
    if (isMulti) {
      return GestureDetector(
        onTap: () => prov.toggleFolderSelect(folder.id),
        child: _buildCard(
          context,
          theme,
          color,
          isDragOver: false,
          isSelected: isFolderSelected,
          showCheckbox: true,
        ),
      );
    }

    // 普通模式：点击进入文件夹，右键菜单，支持拖入表情包
    return DragTarget<Meme>(
      onAcceptWithDetails: (details) {
        final p = context.read<MemeProvider>();
        p.moveToFolder(details.data.id, folder.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移至「${folder.name}」'), duration: const Duration(seconds: 1)),
        );
      },
      builder: (ctx, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () {
            final p = context.read<MemeProvider>();
            p.selectFolder(folder.id);
          },
          onSecondaryTapUp: (details) {
            _showFolderContextMenu(details.globalPosition, context, folder, count);
          },
          child: _buildCard(
            context,
            theme,
            color,
            isDragOver: isDragOver,
            isSelected: false,
            showCheckbox: false,
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    ThemeData theme,
    Color color, {
    required bool isDragOver,
    required bool isSelected,
    required bool showCheckbox,
  }) {
    final prov = context.read<MemeProvider>();
    // 获取封面 meme：用户自选 > 文件夹内第一个
    final coverMemeId = folder.coverMemeId ?? prov.memesInFolder(folder.id).firstOrNull?.id;
    final coverMeme = coverMemeId != null
        ? prov.memes.where((m) => m.id == coverMemeId).firstOrNull
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : isDragOver
                  ? color
                  : isActive
                      ? color.withValues(alpha: 0.6)
                      : Colors.transparent,
          width: isSelected ? 3 : 2,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景层：封面图片或纯色
          if (coverMeme != null)
            FutureBuilder<Uint8List?>(
              future: context.read<StorageService>().readMemeBytes(coverMeme.filePath),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
                  return _buildFallback(theme, color);
                }
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              },
            )
          else
            _buildFallback(theme, color),

          // 渐变遮罩，让文字可读
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),

          // 文件夹角标（右上角）
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder, size: 12, color: color.withValues(alpha: 0.9)),
                  const SizedBox(width: 2),
                  Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

          // 文件夹名称（底部）
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),

          // 多选复选框
          if (showCheckbox)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : const SizedBox(width: 14, height: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallback(ThemeData theme, Color color) {
    return Container(
      color: isDragOver
          ? color.withValues(alpha: 0.2)
          : isActive
              ? color.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: Icon(Icons.folder, size: 40, color: color.withValues(alpha: 0.6)),
      ),
    );
  }

  void _showFolderContextMenu(Offset globalPos, BuildContext context, MemeFolder folder, int count) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(globalPos);
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
        Offset.zero & renderBox.size,
      ),
      items: <PopupMenuEntry>[
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
                  final isCover = meme.id == folder.coverMemeId;
                  return GestureDetector(
                    onTap: () {
                      context.read<StorageService>().updateFolderCover(folder.id, meme.id);
                      Navigator.pop(dCtx);
                    },
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                        ),
                        if (isCover)
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
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<StorageService>().updateFolderCover(folder.id, null);
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
    );
  }
}
