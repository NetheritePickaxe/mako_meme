import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/folder.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/storage_service.dart';

class FolderCard extends StatelessWidget {
  final MemeFolder folder;
  final int count;
  final bool isActive;
  final VoidCallback? onSelected;

  const FolderCard({
    super.key,
    required this.folder,
    required this.count,
    this.isActive = false,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(folder.colorValue);
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;
    final isMulti = prov.isMulti;
    final isFolderSelected = prov.selectedFolders.contains(folder.id);

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
              onSelected?.call();
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
          _buildBackground(context, color, isDragOver),
          _buildCoverImage(context, color),
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
          if (folder.coverMemeId != null)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackground(BuildContext context, Color color, bool isDragOver) {
    return Container(
      color: isDragOver
          ? color.withValues(alpha: 0.2)
          : isActive
              ? color.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
    );
  }

  Widget _buildCoverImage(BuildContext context, Color color) {
    if (folder.coverMemeId == null) {
      return Center(
        child: Icon(Icons.folder, size: 48, color: color.withValues(alpha: 0.6)),
      );
    }
    final prov = context.read<MemeProvider>();
    final meme = prov.getMemeById(folder.coverMemeId!);
    if (meme == null || meme.filePath.isEmpty) {
      return Center(
        child: Icon(Icons.folder, size: 48, color: color.withValues(alpha: 0.6)),
      );
    }
    return _FolderCoverImage(meme: meme, color: color);
  }

  void _showFolderContextMenu(Offset globalPos, BuildContext context, MemeFolder folder) {
    final l10n = context.read<LocaleProvider>().l10n;
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(globalPos);
    final hasCover = folder.coverMemeId != null;
    showMenu(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          value: 'set_cover',
          child: ListTile(leading: const Icon(Icons.image_outlined), title: Text(l10n.tr('set_cover')), dense: true),
        ),
        if (hasCover)
          PopupMenuItem<String>(
            value: 'remove_cover',
            child: ListTile(leading: const Icon(Icons.image_not_supported_outlined), title: Text(l10n.tr('remove_cover')), dense: true),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(l10n.tr('delete')), dense: true),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      if (!context.mounted) return;
      final prov = context.read<MemeProvider>();
      if (value == 'rename') {
        _showRenameDialog(context, folder);
      } else if (value == 'delete') {
        _confirmDeleteFolder(context, prov, folder);
      } else if (value == 'set_cover') {
        await _pickAndSetCover(context, folder, prov);
      } else if (value == 'remove_cover') {
        await prov.removeFolderCover(folder.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.tr('cover_removed')), duration: const Duration(seconds: 1)),
          );
        }
      }
    });
  }

  Future<void> _pickAndSetCover(BuildContext context, MemeFolder folder, MemeProvider prov) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;
    final imported = await prov.importFiles(result.files);
    if (imported.isNotEmpty) {
      await prov.setFolderCover(folder.id, imported.first.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('cover_set_success')), duration: const Duration(seconds: 1)),
        );
      }
    }
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

class _FolderCoverImage extends StatefulWidget {
  final Meme meme;
  final Color color;

  const _FolderCoverImage({required this.meme, required this.color});

  @override
  State<_FolderCoverImage> createState() => _FolderCoverImageState();
}

class _FolderCoverImageState extends State<_FolderCoverImage> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = context.read<StorageService>();
    final bytes = await storage.readMemeBytes(widget.meme.filePath);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _bytes == null) {
      return Center(
        child: Icon(Icons.folder, size: 48, color: widget.color.withValues(alpha: 0.6)),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(Icons.folder, size: 48, color: widget.color.withValues(alpha: 0.6)),
      ),
    );
  }
}
