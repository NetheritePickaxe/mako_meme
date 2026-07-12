import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
import '../widgets/meme_preview_panel.dart';
import '../services/storage_service.dart';
import '../screens/settings_screen.dart';
import '../screens/text_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragOver = false;
  // 0=表情包, 1=文件夹, 2=收藏, 3=设置
  int _currentTab = 0;

  void _onTabChanged(int i) {
    final prov = context.read<MemeProvider>();
    if (i == 3) {
      // 设置：打开设置页，不切换标签
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    prov.clearPreviewMeme();
    setState(() {
      _currentTab = i;
      if (i == 0) {
        prov.setShowFavorites(false);
        prov.setShowFoldersView(false);
      } else if (i == 1) {
        prov.setShowFavorites(false);
        prov.setShowFoldersView(true);
      } else if (i == 2) {
        prov.setShowFoldersView(false);
        prov.setShowFavorites(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: _buildLeading(prov, l10n),
        title: Text(_getTitle(prov, l10n)),
        actions: _buildActions(prov, l10n),
        bottom: prov.isMulti ? const PreferredSize(
          preferredSize: Size.fromHeight(48),
          child: MultiSelectBar(),
        ) : null,
      ),
      drawer: _currentTab == 0 ? _buildDrawer(context, prov) : null,
      body: _buildBody(prov, l10n),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: _onTabChanged,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library, color: theme.colorScheme.onSurface),
            label: l10n.tr('nav_memes'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder, color: theme.colorScheme.onSurface),
            label: l10n.tr('nav_folders'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite, color: theme.colorScheme.onSurface),
            label: l10n.tr('favorites'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: theme.colorScheme.onSurface),
            label: l10n.tr('settings'),
          ),
        ],
      ),
      floatingActionButton: _buildFab(prov),
    );
  }

  Widget _buildLeading(MemeProvider prov, L10n l10n) {
    // 表情包标签：进入文件夹时显示返回，否则显示菜单
    if (_currentTab == 0 && prov.folderId != null) {
      return IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: l10n.tr('back'),
        onPressed: () => prov.selectFolder(null),
      );
    }
    if (_currentTab == 0) {
      return Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: l10n.tr('menu'),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _buildActions(MemeProvider prov, L10n l10n) {
    return [
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
    ];
  }

  Widget? _buildFab(MemeProvider prov) {
    final theme = Theme.of(context);
    if (_currentTab == 0) {
      return FloatingActionButton(
        onPressed: () => _showImportMenu(context, prov),
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(CupertinoIcons.add, size: 30, color: theme.colorScheme.onPrimaryContainer),
      );
    }
    if (_currentTab == 1) {
      return FloatingActionButton(
        onPressed: () => _showCreateFolderDialog(context, prov),
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.create_new_folder_outlined, color: theme.colorScheme.onPrimaryContainer),
      );
    }
    return null;
  }

  Widget _buildBody(MemeProvider prov, L10n l10n) {
    switch (_currentTab) {
      case 1:
        return _buildFoldersGrid(prov);
      case 2:
        return _buildMemesListView(prov, l10n);
      case 0:
      default:
        return _buildMemesListView(prov, l10n);
    }
  }

  /// 表情包/收藏的通用列表视图：搜索栏 + 分类筛选 + 网格
  Widget _buildMemesListView(MemeProvider prov, L10n l10n) {
    final settings = context.watch<SettingsProvider>();
    // 横屏预览模式：桌面/Web + 宽屏 + 设置开启
    final isLandscape = _isDesktopOrWeb() &&
        settings.landscapePreview &&
        MediaQuery.sizeOf(context).width >= 900;

    return DropTarget(
      onDragDone: (detail) async {
        final validExts = Meme.supportedExtensions;
        final files = detail.files.where((f) {
          return validExts.contains(f.name.split('.').last.toLowerCase());
        }).toList();
        if (files.isNotEmpty) {
          final storage = context.read<StorageService>();
          final settingsProvider = context.read<SettingsProvider>();
          for (final f in files) {
            await storage.importFile(
              PlatformFile(
                name: f.name,
                size: await f.length(),
                path: f.path,
              ),
              autoClassify: settingsProvider.autoClassify,
              classifyRatio: settingsProvider.classifyRatio,
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
            Row(
              children: [
                // 左侧预览面板
                if (isLandscape)
                  MemePreviewPanel(
                    meme: prov.previewMeme,
                    onClose: () => prov.clearPreviewMeme(),
                  ),
                // 右侧主内容
                Expanded(
                  child: Column(
                    children: [
                      custom.MakoSearchBar(onSearch: (q) => prov.setQuery(q)),
                      _buildCategoryChips(prov),
                      if (prov.tagFilter.isNotEmpty || prov.folderFilter.isNotEmpty) _buildFilterChips(prov),
                      Expanded(
                        child: MemeGrid(
                          memes: prov.memes,
                          previewMode: isLandscape,
                        ),
                      ),
                    ],
                  ),
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
    );
  }

  /// 是否为桌面端或 Web
  bool _isDesktopOrWeb() {
    if (kIsWeb) return true;
    final p = defaultTargetPlatform;
    return p == TargetPlatform.windows || p == TargetPlatform.macOS || p == TargetPlatform.linux;
  }

  String _getTitle(MemeProvider prov, L10n l10n) {
    if (prov.isMulti) return l10n.tr('selected_count', args: {'count': prov.selected.length.toString()});
    switch (_currentTab) {
      case 1:
        return l10n.tr('browse_folders');
      case 2:
        return l10n.tr('favorites');
      case 0:
      default:
        if (prov.folderId != null) {
          return prov.folders.where((f) => f.id == prov.folderId).firstOrNull?.name ?? 'Mako Meme';
        }
        return 'Mako Meme';
    }
  }

  Widget _buildFoldersGrid(MemeProvider prov) {
    final settings = context.watch<SettingsProvider>();
    final l10n = context.read<LocaleProvider>().l10n;
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
            Text(l10n.tr('no_folders'), style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.outline)),
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
          onSelected: () => setState(() => _currentTab = 0),
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
            // 头部：Logo + 统计信息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.emoji_emotions_outlined, color: theme.colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text('Mako Meme', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _drawerStatChip(theme, Icons.photo_library, prov.allMemesCount.toString()),
                      _drawerStatChip(theme, Icons.folder_outlined, prov.folders.length.toString()),
                      _drawerStatChip(theme, Icons.favorite, prov.favorites.length.toString()),
                    ],
                  ),
                ],
              ),
            ),
            // 文件夹快速访问
            Expanded(
              child: prov.folders.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 56, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(l10n.tr('no_folders'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(l10n.tr('folder'), style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600,
                          )),
                        ),
                        ...prov.folders.map((f) => _drawerFolderItem(context, prov, f)),
                      ],
                    ),
            ),
            // 底部：新建文件夹
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(l10n.tr('new_folder')),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateFolderDialog(context, prov);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerStatChip(ThemeData theme, IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(value, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _drawerFolderItem(BuildContext context, MemeProvider prov, MemeFolder folder) {
    final theme = Theme.of(context);
    final isActive = prov.folderId == folder.id;
    return ListTile(
      leading: Icon(Icons.folder, color: Color(folder.colorValue).withValues(alpha: 0.8), size: 22),
      title: Text(folder.name, style: TextStyle(
        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        color: isActive ? theme.colorScheme.primary : null,
      )),
      trailing: Text('${prov.countInFolder(folder.id)}', style: TextStyle(
        fontSize: 12,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      )),
      onTap: () {
        prov.selectFolder(folder.id);
        Navigator.pop(context);
        setState(() => _currentTab = 0);
      },
      onLongPress: () => _showFolderMenu(context, prov, folder),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildCategoryChips(MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    final settings = context.watch<SettingsProvider>();
    final categories = <Map<String, String>>[
      {'type': Meme.typeEmoji, 'label': l10n.tr('cat_emoji')},
      {'type': Meme.typeGif, 'label': l10n.tr('cat_gif')},
      {'type': Meme.typeImage, 'label': l10n.tr('cat_image')},
      {'type': Meme.typeText, 'label': l10n.tr('cat_text')},
      {'type': Meme.typePortrait, 'label': l10n.tr('cat_portrait')},
      {'type': Meme.typeCg, 'label': l10n.tr('cat_cg')},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('cat_character_card')},
      {'type': Meme.typeVector, 'label': l10n.tr('cat_vector')},
      {'type': Meme.typePsd, 'label': l10n.tr('cat_psd')},
      {'type': Meme.typePdf, 'label': l10n.tr('cat_pdf')},
      {'type': Meme.typeManga, 'label': l10n.tr('cat_manga')},
      {'type': Meme.typeNovel, 'label': l10n.tr('cat_novel')},
      // 用户自定义分类
      ...settings.customCategories.map((c) => {'type': c, 'label': c}),
    ];

    // 过滤掉隐藏的分类
    final visibleCategories = categories
        .where((c) => settings.isCategoryVisible(c['type']!))
        .toList();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: visibleCategories.length + 1,
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

          final cat = visibleCategories[i - 1];
          final type = cat['type']!;
          final label = cat['label']!;
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
              leading: const Icon(Icons.menu_book),
              title: Text(l10n.tr('import_novel')),
              subtitle: Text(l10n.tr('novel_desc')),
              onTap: () { Navigator.pop(bCtx); _importNovel(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.tr('import_manga')),
              subtitle: Text(l10n.tr('manga_desc')),
              onTap: () { Navigator.pop(bCtx); _showMangaImportMenu(ctx, prov); },
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
      allowedExtensions: Meme.supportedExtensions,
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
    _showTextEditor(ctx, prov, type: Meme.typeText);
  }

  void _importNovel(BuildContext ctx, MemeProvider prov) {
    _showTextEditor(ctx, prov, type: Meme.typeNovel);
  }

  /// 漫画导入子菜单：手动多图 / CBZ、ZIP 压缩包
  void _showMangaImportMenu(BuildContext ctx, MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    showModalBottomSheet(
      context: ctx,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.collections),
              title: Text(l10n.tr('manga_from_images')),
              subtitle: Text(l10n.tr('manga_from_images_desc')),
              onTap: () { Navigator.pop(bCtx); _importMangaFromImages(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip),
              title: Text(l10n.tr('manga_from_archive')),
              subtitle: Text(l10n.tr('manga_from_archive_desc')),
              onTap: () { Navigator.pop(bCtx); _importMangaFromArchive(ctx, prov); },
            ),
          ],
        ),
      ),
    );
  }

  /// 手动多图合并为漫画
  Future<void> _importMangaFromImages(BuildContext ctx, MemeProvider prov) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!ctx.mounted) return;

    // 让用户输入名称
    final name = await showDialog<String>(
      context: ctx,
      builder: (dCtx) {
        final ctrl = TextEditingController(text: result.files.first.name.split('.').first);
        return AlertDialog(
          title: Text(l10n.tr('import_manga')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.tr('manga_pages_count')}: ${result.files.length}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(hintText: l10n.tr('manga_name_hint')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()), child: Text(l10n.tr('import'))),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    if (!ctx.mounted) return;

    try {
      await prov.importMangaFromFiles(result.files, name: name);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('manga_imported', args: {'count': result.files.length.toString()}))),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('import_failed'))),
        );
      }
    }
  }

  /// 从 CBZ/ZIP 压缩包导入漫画
  Future<void> _importMangaFromArchive(BuildContext ctx, MemeProvider prov) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cbz', 'zip'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!ctx.mounted) return;
    final archive = result.files.first;

    try {
      final meme = await prov.importMangaFromArchive(archive);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('manga_imported', args: {'count': meme.pages.length.toString()}))),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('import_failed'))),
        );
      }
    }
  }

  /// 全屏文本/小说编辑器，支持 Markdown 实时预览切换
  void _showTextEditor(BuildContext ctx, MemeProvider prov, {required String type}) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TextEditorScreen(type: type, onSave: (text, title) async {
          await prov.importText(text, name: title, type: type);
        }),
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
