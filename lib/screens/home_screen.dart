import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/settings_provider.dart';
import '../l10n/l10n.dart';
import '../models/meme.dart';
import '../models/folder.dart';
import '../widgets/meme_grid.dart';
import '../widgets/folder_card.dart';
import '../widgets/mako_search_bar.dart' as custom;
import '../widgets/multi_select_bar.dart';
import '../services/storage_service.dart';
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
            if (prov.folderId != null || prov.showFoldersView) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.tr('back'),
                onPressed: () {
                  if (prov.folderId != null) {
                    prov.selectFolder(null);
                  } else {
                    prov.setShowFoldersView(false);
                  }
                },
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
          final validExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'apng', 'psd'];
          final files = detail.files.where((f) {
            return validExts.contains(f.name.split('.').last.toLowerCase());
          }).toList();
          if (files.isNotEmpty) {
            final storage = context.read<StorageService>();
            final settings = context.read<SettingsProvider>();
            for (final f in files) {
              // 直接用 path 流式拷贝，避免一次性读取超大文件导致 OOM
              await storage.importFile(
                PlatformFile(
                  name: f.name,
                  size: await f.length(),
                  path: f.path,
                ),
                autoClassify: settings.autoClassify,
                classifyRatio: settings.classifyRatio,
              );
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
                  _buildCategoryChips(prov),
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
    if (prov.showFoldersView) return l10n.tr('browse_folders');
    if (prov.folderId == null) return 'Mako Meme';
    return prov.folders.where((f) => f.id == prov.folderId).firstOrNull?.name ?? 'Mako Meme';
  }

  Widget _buildMixedGrid(MemeProvider prov) {
    // 进入文件夹：显示该文件夹内的 meme
    if (prov.folderId != null) {
      return MemeGrid(memes: prov.memes);
    }

    // 浏览文件夹视图：显示文件夹卡片
    if (prov.showFoldersView) {
      return _buildFoldersGrid(prov);
    }

    // 根视图“全部”：显示所有表情（无视文件夹归属）
    return MemeGrid(memes: prov.memes);
  }

  Widget _buildFoldersGrid(MemeProvider prov) {
    final settings = context.watch<SettingsProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final cols = settings.gridColumns > 0
        ? settings.gridColumns
        : width > 1200 ? 6 : width > 900 ? 5 : width > 600 ? 4 : width > 400 ? 3 : 2;

    if (prov.folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10nForContext().tr('no_memes'), style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }

    return MasonryGridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: const EdgeInsets.all(8),
      itemCount: prov.folders.length,
      itemBuilder: (ctx, i) {
        final f = prov.folders[i];
        return FolderCard(
          folder: f,
          count: prov.countInFolder(f.id),
          isActive: prov.folderId == f.id,
        );
      },
    );
  }

  L10n l10nForContext() => context.read<LocaleProvider>().l10n;

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
                    isActive: prov.folderId == null && !prov.showFoldersView,
                    onTap: () { prov.selectFolder(null); prov.setShowFoldersView(false); Navigator.pop(context); },
                  ),
                  _drawerItem(
                    icon: Icons.folder_outlined,
                    label: l10n.tr('browse_folders'),
                    count: prov.folders.length,
                    isActive: prov.showFoldersView,
                    onTap: () { prov.setShowFoldersView(true); Navigator.pop(context); },
                  ),
                  _drawerItem(
                    icon: Icons.favorite,
                    label: l10n.tr('favorites'),
                    count: prov.favorites.length,
                    isActive: false,
                    onTap: () { Navigator.pop(context); },
                  ),
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
                    onTap: () { prov.selectFolder(f.id); Navigator.pop(context); },
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

  Widget _buildCategoryChips(MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    final categories = [
      {'type': Meme.typeEmoji, 'label': l10n.tr('cat_emoji')},
      {'type': Meme.typeGif, 'label': l10n.tr('cat_gif')},
      {'type': Meme.typeImage, 'label': l10n.tr('cat_image')},
      {'type': Meme.typeText, 'label': l10n.tr('cat_text')},
      {'type': Meme.typePortrait, 'label': l10n.tr('cat_portrait')},
      {'type': Meme.typeCg, 'label': l10n.tr('cat_cg')},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('cat_character_card')},
      {'type': Meme.typeVector, 'label': l10n.tr('cat_vector')},
      {'type': Meme.typePsd, 'label': l10n.tr('cat_psd')},
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final cs = Theme.of(ctx).colorScheme;

          // 第一个是"全部"
          if (i == 0) {
            final selected = prov.typeFilter.isEmpty;
            return _buildRoundedChip(
              context: ctx,
              label: l10n.tr('cat_all'),
              selected: selected,
              colorScheme: cs,
              onTap: () => prov.clearTypeFilter(),
            );
          }

          final cat = categories[i - 1];
          final type = cat['type'] as String;
          final label = cat['label'] as String;
          final selected = prov.typeFilter.contains(type);

          return _buildRoundedChip(
            context: ctx,
            label: label,
            selected: selected,
            colorScheme: cs,
            onTap: () {
              if (selected) {
                prov.clearTypeFilter();
              } else {
                prov.setTypeFilter(type);
              }
            },
          );
        },
      ),
    );
  }

  /// 圆形（stadium）分类按钮 — 纯文字，无图标
  Widget _buildRoundedChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
          )),
        ),
      ),
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
            ListTile(
              leading: const Icon(Icons.image),
              title: Text(l10n.tr('import_images')),
              subtitle: const Text('JPG / PNG / GIF / WebP / BMP'),
              onTap: () { Navigator.pop(bCtx); _importFiles(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(l10n.tr('import_text')),
              subtitle: Text(l10n.tr('plain_text_or_emoji')),
              onTap: () { Navigator.pop(bCtx); _importText(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: Text(l10n.tr('new_folder')),
              onTap: () { Navigator.pop(bCtx); _showCreateFolderDialog(ctx, prov); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l10n.tr('import_backup')),
              subtitle: Text(l10n.tr('import_data_desc')),
              onTap: () { Navigator.pop(bCtx); _importZip(ctx); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFiles(BuildContext ctx, MemeProvider prov) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp',
        'svg', 'apng', 'psd',
      ],
    );
    if (result != null && result.files.isNotEmpty) {
      final settings = context.read<SettingsProvider>();
      await prov.importFiles(
        result.files,
        autoClassify: settings.autoClassify,
        classifyRatio: settings.classifyRatio,
      );
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
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: l10n.tr('paste'),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null && data!.text!.isNotEmpty) {
                ctrl.text = data.text!;
              }
            },
          ),
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
