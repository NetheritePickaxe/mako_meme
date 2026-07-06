import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/l10n.dart';
import '../models/meme.dart';
import '../models/mood.dart';
import '../models/folder.dart';
import '../widgets/meme_grid.dart';
import '../widgets/folder_card.dart';
import '../widgets/mako_search_bar.dart' as custom;
import '../widgets/multi_select_bar.dart';
import '../services/storage_service.dart';
import '../screens/meme_viewer_screen.dart';
import '../screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) {
            if (prov.folderId != null) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => prov.selectFolder(null),
              );
            }
            return IconButton(
              icon: const Icon(Icons.menu),
              tooltip: l10n.tr('menu'),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            );
          },
        ),
        title: Text(_getTitle(prov, l10n)),
        actions: [
          IconButton(
            icon: Icon(prov.isMulti ? Icons.close : Icons.checklist),
            tooltip: prov.isMulti ? l10n.tr('exit_multi_select') : l10n.tr('multi_select'),
            onPressed: () => prov.toggleMulti(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: l10n.tr('sort'),
            onSelected: (v) {
              switch (v) {
                case 'date': prov.setSort(SortBy.date); break;
                case 'name': prov.setSort(SortBy.name); break;
                case 'size': prov.setSort(SortBy.size); break;
                case 'order': prov.toggleOrder(); break;
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'date', checked: prov.sortBy == SortBy.date, child: Text(l10n.tr('sort_by_date'))),
              CheckedPopupMenuItem(value: 'name', checked: prov.sortBy == SortBy.name, child: Text(l10n.tr('sort_by_name'))),
              CheckedPopupMenuItem(value: 'size', checked: prov.sortBy == SortBy.size, child: Text(l10n.tr('sort_by_size'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'order', child: Text(prov.order == SortOrder.asc ? '↑ ${l10n.tr('asc')}' : '↓ ${l10n.tr('desc')}')),
            ],
          ),
        ],
        bottom: prov.isMulti ? const PreferredSize(
          preferredSize: Size.fromHeight(48),
          child: MultiSelectBar(),
        ) : null,
      ),
      drawer: _buildDrawer(context, prov),
      body: DropTarget(
        onDragDone: (detail) async {
          final validExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
          final files = detail.files.where((f) {
            return validExts.contains(f.name.split('.').last.toLowerCase());
          }).toList();
          if (files.isNotEmpty) {
            final storage = context.read<StorageService>();
            for (final f in files) {
              final bytes = await f.readAsBytes();
              await storage.importFile(PlatformFile(
                name: f.name,
                size: bytes.length,
                bytes: bytes,
                path: f.path,
              ));
            }
            await prov.loadAll();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.tr('imported_images', args: {'count': files.length.toString()})), duration: const Duration(seconds: 2)),
              );
            }
          }
        },
        onDragEntered: (_) => setState(() => _dragOver = true),
        onDragExited: (_) => setState(() => _dragOver = false),
        child: LayoutBuilder(
          builder: (ctx, constraints) => Stack(
            children: [
              Column(
                children: [
                  custom.MakoSearchBar(onSearch: (q) => prov.setQuery(q)),
                  if (prov.tagFilter.isNotEmpty || prov.folderFilter.isNotEmpty) _buildFilterChips(prov),
                  Expanded(
                    child: _buildMixedGrid(prov),
                  ),
                ],
              ),
              if (_dragOver)
                Positioned.fill(
                  child: Container(
                    color: Colors.black45,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_upload, size: 48, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 8),
                            Text(l10n.tr('drop_to_import'), style: TextStyle(
                              fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showImportMenu(context, prov),
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        child: Icon(CupertinoIcons.add, size: 30, color: Theme.of(context).colorScheme.onTertiaryContainer),
      ),
    );
  }

  String _getTitle(MemeProvider prov, L10n l10n) {
    if (prov.isMulti) return l10n.tr('selected_count', args: {'count': prov.selected.length.toString()});
    if (prov.moodFilter != null) {
      final m = findMoodById(prov.moodFilter);
      return m != null ? '${m.name} ${l10n.tr('scene')}' : 'Mako Meme';
    }
    if (prov.folderId == null) return 'Mako Meme';
    return prov.folders.where((f) => f.id == prov.folderId).firstOrNull?.name ?? 'Mako Meme';
  }

  Widget _buildMixedGrid(MemeProvider prov) {
    if (prov.folderId != null || prov.moodFilter != null) {
      return MemeGrid(memes: prov.memes);
    }

    final folders = prov.folders;
    final uncategorized = prov.memes.where((m) => m.folderId == null).toList();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final cols = w > 1200 ? 6 : w > 900 ? 5 : w > 600 ? 4 : w > 400 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: folders.length + uncategorized.length,
          itemBuilder: (ctx, i) {
            if (i < folders.length) {
              final f = folders[i];
              return FolderCard(
                folder: f,
                count: prov.countInFolder(f.id),
                isActive: prov.folderId == f.id,
              );
            }
            final meme = uncategorized[i - folders.length];
            return _buildMemeCardInGrid(meme);
          },
        );
      },
    );
  }

  Widget _buildMemeCardInGrid(Meme meme) {
    return FutureBuilder<Uint8List?>(
      future: context.read<StorageService>().readMemeBytes(meme.filePath),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade200,
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          final l10n = context.read<LocaleProvider>().l10n;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade200,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 24, color: Colors.grey.shade500),
                  const SizedBox(height: 4),
                  Text(l10n.tr('lost'), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => MemeViewerScreen(memes: [meme], initialIndex: 0),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(snapshot.data!, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, MemeProvider prov) {
    final theme = Theme.of(context);
    final l10n = context.read<LocaleProvider>().l10n;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              color: theme.colorScheme.primaryContainer.withAlpha(80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mako Meme', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(l10n.tr('total_memes', args: {'count': prov.allMemesCount.toString()}), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerItem(
                    icon: Icons.all_inbox,
                    label: l10n.tr('all_memes'),
                    count: prov.allMemesCount,
                    isActive: prov.folderId == null && prov.moodFilter == null,
                    onTap: () { prov.selectFolder(null); prov.clearMood(); Navigator.pop(context); },
                  ),
                  _drawerItem(
                    icon: Icons.favorite,
                    label: l10n.tr('favorites'),
                    count: prov.favorites.length,
                    isActive: false,
                    onTap: () { prov.selectMood(null); Navigator.pop(context); },
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(l10n.tr('scene'), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withAlpha(120))),
                  ),
                  ...presetMoods.map((m) => _drawerItem(
                    icon: m.icon,
                    iconColor: m.color,
                    label: m.name,
                    count: prov.moodCounts[m.id] ?? 0,
                    isActive: prov.moodFilter == m.id,
                    onTap: () { prov.selectMood(m.id); prov.selectFolder(null); Navigator.pop(context); },
                  )),
                  const Divider(indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(l10n.tr('folder'), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withAlpha(120))),
                  ),
                  ...prov.folders.map((f) => _drawerItem(
                    icon: Icons.folder,
                    label: f.name,
                    count: prov.countInFolder(f.id),
                    isActive: prov.folderId == f.id,
                    onTap: () { prov.selectFolder(f.id); prov.clearMood(); Navigator.pop(context); },
                    onLongPress: () => _showFolderMenu(context, prov, f),
                  )),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.settings, size: 20),
                    title: Text(l10n.tr('settings')),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    },
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
    Color? iconColor,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: iconColor ?? (isActive ? theme.colorScheme.primary : null), size: 20),
      title: Text(label, style: TextStyle(
        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        color: isActive ? theme.colorScheme.primary : null,
      )),
      trailing: Text('$count', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
      onTap: onTap,
      onLongPress: onLongPress,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildFilterChips(MemeProvider prov) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ...prov.tagFilter.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              label: Text('#$tag', style: const TextStyle(fontSize: 12)),
              onDeleted: () => prov.toggleTag(tag),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )),
          ...prov.folders.where((f) => prov.folderFilter.contains(f.id)).map((f) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              avatar: Icon(Icons.folder, size: 16, color: Color(f.colorValue)),
              label: Text('@${f.name}', style: const TextStyle(fontSize: 12)),
              onDeleted: () => prov.toggleFolderFilter(f.id),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )),
        ],
      ),
    );
  }

  void _showImportMenu(BuildContext ctx, MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    showModalBottomSheet(
      context: ctx,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prov.folderId == null) ...[
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: Text(l10n.tr('new_folder')),
                onTap: () { Navigator.pop(bCtx); _showCreateFolderDialog(ctx, prov); },
              ),
              const Divider(),
            ],
            ListTile(
              leading: const Icon(Icons.image),
              title: Text(l10n.tr('import_images')),
              subtitle: const Text('JPG / PNG / GIF / WebP / BMP'),
              onTap: () { Navigator.pop(bCtx); _importFiles(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(l10n.tr('import_text')),
              subtitle: const Text('Plain text or Emoji'),
              onTap: () { Navigator.pop(bCtx); _importText(ctx, prov); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l10n.tr('import_backup')),
              subtitle: const Text('ZIP backup / 批量导入'),
              onTap: () { Navigator.pop(bCtx); _importZip(ctx); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFiles(BuildContext ctx, MemeProvider prov) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      await prov.importFiles(result.files);
    }
  }

  void _importText(BuildContext ctx, MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    final ctrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('import_text')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: l10n.tr('hint_text_or_emoji')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              prov.importText(ctrl.text.trim());
              Navigator.pop(dCtx);
            }
          }, child: Text(l10n.tr('import'))),
        ],
      ),
    );
  }

  Future<void> _importZip(BuildContext ctx) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!ctx.mounted) return;
    final zipFile = result.files.first;
    if (zipFile.path == null) return;

    final storage = ctx.read<StorageService>();
    final prov = ctx.read<MemeProvider>();

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('import_backup')),
        content: Text(l10n.tr('import_confirm', args: {'filename': zipFile.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(l10n.tr('import'))),
        ],
      ),
    );
    if (!ctx.mounted) return;
    if (confirmed != true) return;

    final count = await storage.importZip(zipFile.path!);
    await prov.loadAll();

    if (ctx.mounted) {
      String msg;
      if (count == 0) {
        msg = l10n.tr('import_success');
      } else if (count > 0) {
        msg = l10n.tr('imported_count', args: {'count': count.toString()});
      } else {
        msg = l10n.tr('import_failed');
      }
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showCreateFolderDialog(BuildContext ctx, MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    final ctrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('new_folder')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.tr('folder_name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              prov.createFolder(ctrl.text.trim());
              Navigator.pop(dCtx);
            }
          }, child: Text(l10n.tr('create'))),
        ],
      ),
    );
  }

  void _showFolderMenu(BuildContext ctx, MemeProvider prov, MemeFolder folder) {
    final l10n = context.read<LocaleProvider>().l10n;
    showModalBottomSheet(
      context: ctx,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.tr('rename')),
              onTap: () { Navigator.pop(bCtx); _renameFolder(ctx, prov, folder); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(l10n.tr('delete'), style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(bCtx);
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: Text(l10n.tr('delete_folder')),
                    content: Text(l10n.tr('delete_folder_confirm', args: {'name': folder.name})),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.tr('cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: Text(l10n.tr('delete'))),
                    ],
                  ),
                );
                if (confirm == true) await prov.deleteFolder(folder.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _renameFolder(BuildContext ctx, MemeProvider prov, MemeFolder folder) {
    final l10n = context.read<LocaleProvider>().l10n;
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('rename')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: l10n.tr('new_name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              prov.renameFolder(folder.id, ctrl.text.trim());
              Navigator.pop(dCtx);
            }
          }, child: Text(l10n.tr('save'))),
        ],
      ),
    );
  }
}
