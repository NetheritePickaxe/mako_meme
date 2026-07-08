import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/folder.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';

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
    final l10n = context.watch<LocaleProvider>().l10n;
    final isMulti = prov.isMulti;
    final isFolderSelected = prov.selectedFolders.contains(folder.id);

    // 多选模式：点击切换选中，显示复选框，禁用拖放
    if (isMulti) {
      return AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () => prov.toggleFolderSelect(folder.id),
          child: _buildCard(
            context,
            theme,
            color,
            isDragOver: false,
            isSelected: isFolderSelected,
            showCheckbox: true,
          ),
        ),
      );
    }

    // 普通模式：点击进入文件夹，右键菜单，支持拖入表情包
    return AspectRatio(
      aspectRatio: 1,
      child: DragTarget<Meme>(
        onAcceptWithDetails: (details) {
          final p = context.read<MemeProvider>();
          p.moveToFolder(details.data.id, folder.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.tr('moved_to_folder_msg', args: {'name': folder.name})), duration: const Duration(seconds: 1)),
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
              _showFolderContextMenu(details.globalPosition, context, folder);
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
      ),
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
          // 纯色背景
          Container(
            color: isDragOver
                ? color.withValues(alpha: 0.2)
                : isActive
                    ? color.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Center(
              child: Icon(Icons.folder, size: 40, color: color.withValues(alpha: 0.6)),
            ),
          ),

          // 文件夹名称（底部左侧）
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
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

  void _showFolderContextMenu(Offset globalPos, BuildContext context, MemeFolder folder) {
    final l10n = context.read<LocaleProvider>().l10n;
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(globalPos);
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
        Offset.zero & renderBox.size,
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(leading: const Icon(Icons.edit), title: Text(l10n.tr('rename')), dense: true),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(l10n.tr('delete')), dense: true),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      final prov = context.read<MemeProvider>();
      if (value == 'rename') {
        _showRenameDialog(context, folder);
      } else if (value == 'delete') {
        _confirmDeleteFolder(context, prov, folder);
      }
    });
  }

  void _showRenameDialog(BuildContext context, MemeFolder folder) {
    final l10n = context.read<LocaleProvider>().l10n;
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.tr('folder_name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<MemeProvider>().renameFolder(folder.id, name);
              }
              Navigator.pop(dCtx);
            },
            child: Text(l10n.tr('confirm')),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(BuildContext context, MemeProvider prov, MemeFolder folder) {
    final l10n = context.read<LocaleProvider>().l10n;
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('delete_folder')),
        content: Text(l10n.tr('delete_folder_confirm', args: {'name': folder.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () {
              prov.deleteFolder(folder.id);
              Navigator.pop(dCtx);
            },
            child: Text(l10n.tr('delete')),
          ),
        ],
      ),
    );
  }
}
