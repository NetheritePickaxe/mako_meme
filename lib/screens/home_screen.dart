import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
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
  // 0=表情包, 1=文件夹, 2=收藏, 3=情绪（仅 tagSubdivision 开启时可用）
  int _currentTab = 0;
  // 文件夹/情绪页面的本地搜索关键字
  String _folderQuery = '';
  String _moodQuery = '';

  // 底部导航位置 ↔ 内部 tab 语义转换（收藏与文件夹位置已交换）
  // nav: 0=表情 1=收藏 2=文件夹 3=情绪
  // logic: 0=表情 1=文件夹 2=收藏 3=情绪
  int _navToLogic(int nav) {
    if (nav == 1) return 2;
    if (nav == 2) return 1;
    return nav;
  }

  int _logicToNav(int logic) {
    if (logic == 1) return 2;
    if (logic == 2) return 1;
    return logic;
  }

  void _onTabChanged(int i) {
    final prov = context.read<MemeProvider>();
    prov.clearPreviewMeme();
    setState(() {
      _currentTab = i;
      if (i == 0) {
        prov.setShowFavorites(false);
        prov.setShowFoldersView(false);
        prov.setMoodFilter(null);
      } else if (i == 1) {
        prov.setShowFavorites(false);
        prov.setShowFoldersView(true);
        prov.setMoodFilter(null);
      } else if (i == 2) {
        prov.setShowFoldersView(false);
        prov.setShowFavorites(true);
        prov.setMoodFilter(null);
      } else if (i == 3) {
        // 情绪页：清除其他筛选
        prov.setShowFoldersView(false);
        prov.setShowFavorites(false);
        prov.setMoodFilter(null);
      }
    });
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// 点击侧边栏 Logo：弹出满屏 emoji 特效（不关闭抽屉）
  void _showEmojiEffect(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (_) => const _EmojiRainOverlay(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();
    final hasBg = settings.hasCustomBg;
    // 情绪页仅在 tag 细分开启时显示
    final showMoodTab = settings.tagSubdivision;
    // 若 tag 细分被关闭但当前在情绪页，回退到表情包页
    if (!showMoodTab && _currentTab == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onTabChanged(0);
      });
    }
    // 实际 selectedIndex 需要跳过被隐藏的情绪标签，并按交换后的导航位置转换
    final rawNav = _currentTab == 3 ? 3 : _currentTab.clamp(0, showMoodTab ? 3 : 2);
    final navIndex = _logicToNav(rawNav);

    return Scaffold(
      backgroundColor: hasBg ? Colors.transparent : theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: hasBg ? Colors.transparent : theme.colorScheme.surface,
        leading: _buildLeading(prov, l10n),
        title: Text(_getTitle(prov, l10n)),
        actions: _buildActions(prov, l10n),
        bottom: prov.isMulti ? const PreferredSize(
          preferredSize: Size.fromHeight(48),
          child: MultiSelectBar(),
        ) : null,
      ),
      drawer: _buildDrawer(context, prov),
      body: _buildBackgroundedBody(prov, l10n),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) => _onTabChanged(_navToLogic(i)),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library, color: theme.colorScheme.onSurface),
            label: l10n.tr('nav_memes'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite, color: theme.colorScheme.onSurface),
            label: l10n.tr('favorites'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder, color: theme.colorScheme.onSurface),
            label: l10n.tr('nav_folders'),
          ),
          if (showMoodTab)
            NavigationDestination(
              icon: const Icon(Icons.mood_outlined),
              selectedIcon: Icon(Icons.mood, color: theme.colorScheme.onSurface),
              label: l10n.tr('nav_moods'),
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
    // 情绪标签：选了具体情绪时显示返回
    if (_currentTab == 3 && prov.moodFilter != null) {
      return IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: l10n.tr('back'),
        onPressed: () => prov.setMoodFilter(null),
      );
    }
    // 所有页面都有侧边栏按钮
    return Builder(
      builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu),
        tooltip: l10n.tr('menu'),
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      ),
    );
  }

  /// leading 是否被返回按钮占用（文件夹内 / 情绪筛选内）
  bool _leadingIsBack(MemeProvider prov) =>
      (_currentTab == 0 && prov.folderId != null) ||
      (_currentTab == 3 && prov.moodFilter != null);

  List<Widget> _buildActions(MemeProvider prov, L10n l10n) {
    return [
      // 进入文件夹/情绪筛选后 leading 变成返回按钮，这里补一个菜单入口
      if (_leadingIsBack(prov))
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.tr('menu'),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      // 多选模式且选中 1+ 时显示工具按钮
      if (prov.isMulti && prov.selected.isNotEmpty)
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.build_outlined),
            tooltip: l10n.tr('tools'),
            onPressed: () => MultiSelectBar.showToolsMenu(ctx, prov, l10n),
          ),
        ),
      IconButton(
        icon: Icon(prov.isMulti ? Icons.close : Icons.checklist),
        tooltip: prov.isMulti ? l10n.tr('exit_multi_select') : l10n.tr('multi_select'),
        onPressed: () => prov.toggleMulti(),
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.sort),
        tooltip: l10n.tr('sort'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  /// 情绪页：按情绪分类展示表情包
  /// 无筛选时显示所有情绪的网格（带表情包数量），选了情绪后显示该情绪的表情包列表
  Widget _buildMoodsView(MemeProvider prov, L10n l10n) {
    final theme = Theme.of(context);

    // 选了具体情绪：显示该情绪下的表情包
    if (prov.moodFilter != null) {
      return _buildMemesListView(prov, l10n);
    }

    // 情绪网格视图
    final moodGroups = prov.memesByMood;
    if (moodGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mood_bad, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.tr('no_moods'),
              style: TextStyle(fontSize: 18, color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            Text(l10n.tr('no_moods_hint'),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    final moods = moodGroups.keys.toList()..sort((a, b) {
      // 按总权重降序排序
      final aw = moodGroups[a]!.fold<int>(0, (sum, m) {
        return sum + (m.moods.firstWhere((mo) => mo['name'] == a,
            orElse: () => {'weight': 0})['weight'] as int);
      });
      final bw = moodGroups[b]!.fold<int>(0, (sum, m) {
        return sum + (m.moods.firstWhere((mo) => mo['name'] == b,
            orElse: () => {'weight': 0})['weight'] as int);
      });
      return bw.compareTo(aw);
    });
    // 按搜索关键字过滤情绪名
    final filteredMoods = _moodQuery.isEmpty
        ? moods
        : moods.where((name) => name.toLowerCase().contains(_moodQuery.toLowerCase())).toList();

    return Column(
      children: [
        // 搜索栏（情绪名搜索）
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _moodQuery = v),
            decoration: InputDecoration(
              hintText: l10n.tr('search_mood_hint'),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 1.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filteredMoods.length,
            itemBuilder: (ctx, i) {
              final moodName = filteredMoods[i];
              final memes = moodGroups[moodName]!;
              final totalWeight = memes.fold<int>(0, (sum, m) {
                return sum + (m.moods.firstWhere((mo) => mo['name'] == moodName,
                    orElse: () => {'weight': 0})['weight'] as int);
              });
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => prov.setMoodFilter(moodName),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mood, size: 32, color: theme.colorScheme.tertiary),
                        const SizedBox(height: 8),
                        Text(
                          moodName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${memes.length} ${l10n.tr('items_count')}',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.star, size: 12, color: theme.colorScheme.tertiary),
                            const SizedBox(width: 2),
                            Text(
                              '$totalWeight',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.tertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody(MemeProvider prov, L10n l10n) {
    switch (_currentTab) {
      case 1:
        return _buildFoldersGrid(prov);
      case 2:
        return _buildMemesListView(prov, l10n);
      case 3:
        return _buildMoodsView(prov, l10n);
      case 0:
      default:
        return _buildMemesListView(prov, l10n);
    }
  }

  /// 带自定义背景的 body：背景图 + 模糊 + 暗色遮罩 + 原内容
  Widget _buildBackgroundedBody(MemeProvider prov, L10n l10n) {
    final settings = context.watch<SettingsProvider>();
    final body = _buildBody(prov, l10n);

    if (!settings.hasCustomBg) return body;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 遮罩颜色：深色模式用黑色，浅色模式用白色（保证内容可读）
    final overlayColor = isDark ? Colors.black : Colors.white;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景图
        Positioned.fill(
          child: _CustomBackgroundImage(
            path: settings.bgImagePath!,
            blur: settings.bgBlur,
          ),
        ),
        // 暗色/亮色遮罩（保证内容可读）
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: overlayColor.withValues(alpha: settings.bgOpacity),
            ),
          ),
        ),
        // 主内容
        Positioned.fill(child: body),
      ],
    );
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
      case 3:
        return prov.moodFilter ?? l10n.tr('nav_moods');
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
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = settings.gridColumns > 0
        ? settings.gridColumns
        : width > 1200 ? 6 : width > 900 ? 5 : width > 600 ? 4 : width > 400 ? 3 : 2;

    if (prov.folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.tr('no_folders'), style: TextStyle(fontSize: 18, color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 搜索栏（文件夹名搜索）
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _folderQuery = v),
            decoration: InputDecoration(
              hintText: l10n.tr('search_folder_hint'),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: MasonryGridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            padding: const EdgeInsets.all(8),
            itemCount: _filteredFolders(prov).length,
            itemBuilder: (ctx, i) {
              final f = _filteredFolders(prov)[i];
              return FolderCard(
                folder: f,
                count: prov.countInFolder(f.id),
                isActive: prov.folderId == f.id,
                onSelected: () => setState(() => _currentTab = 0),
              );
            },
          ),
        ),
      ],
    );
  }

  List<MemeFolder> _filteredFolders(MemeProvider prov) {
    if (_folderQuery.isEmpty) return prov.folders;
    final q = _folderQuery.toLowerCase();
    return prov.folders.where((f) => f.name.toLowerCase().contains(q)).toList();
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
                      GestureDetector(
                        onTap: () => _showEmojiEffect(context),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/icon_foreground.png',
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                          ),
                        ),
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
            // 底部：新建文件夹 + 设置
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: Text(l10n.tr('new_folder')),
                    onTap: () {
                      Navigator.pop(context);
                      _showCreateFolderDialog(context, prov);
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(l10n.tr('settings')),
                    onTap: () {
                      Navigator.pop(context);
                      _openSettings();
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ],
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
      height: 44,
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

  /// 胶囊状分类按钮 — 纯文字，无图标，文字水平垂直居中
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            height: 1.0,
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
              subtitle: Text(l10n.tr('import_from_gallery')),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: l10n.tr('more_options'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  Navigator.pop(bCtx);
                  if (v == 'manga') {
                    _showMangaImportMenu(ctx, prov);
                  } else if (v == 'sprite') {
                    _showSpriteImportMenu(ctx, prov);
                  } else {
                    _importFiles(ctx, prov);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'normal', child: ListTile(
                    leading: const Icon(Icons.folder_open, size: 20),
                    title: Text(l10n.tr('import_from_files'),
                      style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                  PopupMenuItem(value: 'manga', child: ListTile(
                    leading: const Icon(Icons.photo_library, size: 20),
                    title: Text(l10n.tr('import_as_manga'),
                      style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                  PopupMenuItem(value: 'sprite', child: ListTile(
                    leading: const Icon(Icons.accessibility_new, size: 20),
                    title: Text(l10n.tr('import_as_sprite'),
                      style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                ],
              ),
              onTap: () { Navigator.pop(bCtx); _importFromGallery(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(l10n.tr('import_text')),
              subtitle: Text(l10n.tr('plain_text_or_emoji')),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: l10n.tr('more_options'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  Navigator.pop(bCtx);
                  if (v == 'novel') {
                    _importNovel(ctx, prov);
                  } else if (v == 'text_file') {
                    _importTextFile(ctx, prov);
                  } else {
                    _importText(ctx, prov);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'text', child: ListTile(
                    leading: const Icon(Icons.text_fields, size: 20),
                    title: Text(l10n.tr('import_as_text'),
                      style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                  PopupMenuItem(value: 'novel', child: ListTile(
                    leading: const Icon(Icons.menu_book, size: 20),
                    title: Text(l10n.tr('import_as_novel'),
                      style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                  PopupMenuItem(value: 'text_file', child: ListTile(
                    leading: const Icon(Icons.description_outlined, size: 20),
                    title: Text(l10n.tr('import_text_file'),
                      style: const TextStyle(fontSize: 14)),
                    subtitle: Text(l10n.tr('import_text_file_desc'),
                      style: const TextStyle(fontSize: 11)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                ],
              ),
              onTap: () { Navigator.pop(bCtx); _importText(ctx, prov); },
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
      // 关键：禁止 file_picker 预读 bytes，否则 2GB 大图会 OOM
      // 仅获取 path，导入流程通过 path 流式拷贝
      withData: false,
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

  /// 从系统相册导入图片（仅 Android/iOS）
  Future<void> _importFromGallery(BuildContext ctx, MemeProvider prov) async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(
      limit: 20,
    );
    if (images.isEmpty) return;
    // XFile → PlatformFile
    final files = <PlatformFile>[];
    for (final x in images) {
      final size = await x.length();
      files.add(PlatformFile(
        name: x.name,
        path: x.path,
        size: size,
        bytes: null,
      ));
    }
    if (files.isEmpty) return;
    if (!ctx.mounted) return;
    final settings = context.read<SettingsProvider>();
    await prov.importFiles(
      files,
      autoClassify: settings.autoClassify,
      classifyRatio: settings.classifyRatio,
    );
  }

  void _importText(BuildContext ctx, MemeProvider prov) {
    _showTextEditor(ctx, prov, type: Meme.typeText);
  }

  void _importNovel(BuildContext ctx, MemeProvider prov) {
    _showTextEditor(ctx, prov, type: Meme.typeNovel);
  }

  /// 从文本文件导入（txt / md / doc / docx）
  /// 自动判断类型：大文件/doc/docx/md 视为小说，小 txt 视为文字
  Future<void> _importTextFile(BuildContext ctx, MemeProvider prov) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'markdown', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!ctx.mounted) return;
    int okCount = 0;
    int failCount = 0;
    for (final file in result.files) {
      try {
        await prov.importTextFile(file);
        okCount++;
      } catch (_) {
        failCount++;
      }
    }
    if (!ctx.mounted) return;
    String msg;
    if (failCount == 0) {
      msg = l10n.tr('imported_count', args: {'count': okCount.toString()});
    } else if (okCount == 0) {
      msg = l10n.tr('import_text_file_failed');
    } else {
      msg = '${l10n.tr('imported_count', args: {'count': okCount.toString()})} · $failCount ${l10n.tr('import_text_file_failed')}';
    }
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
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

  /// 立绘/CG 导入子菜单：多图合并 / krkr pjson
  void _showSpriteImportMenu(BuildContext ctx, MemeProvider prov) {
    final l10n = context.read<LocaleProvider>().l10n;
    showModalBottomSheet(
      context: ctx,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.layers),
              title: Text(l10n.tr('sprite_from_images')),
              subtitle: Text(l10n.tr('sprite_from_images_desc')),
              onTap: () { Navigator.pop(bCtx); _importSpriteFromImages(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(l10n.tr('sprite_from_pjson')),
              subtitle: Text(l10n.tr('sprite_from_pjson_desc')),
              onTap: () { Navigator.pop(bCtx); _importSpriteFromPjson(ctx, prov); },
            ),
          ],
        ),
      ),
    );
  }

  /// 多图合并为立绘/CG
  Future<void> _importSpriteFromImages(BuildContext ctx, MemeProvider prov) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    if (result == null || result.files.length < 2) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('sprite_need_multiple'))),
        );
      }
      return;
    }
    if (!ctx.mounted) return;

    // 选择类型：立绘 / CG
    final type = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('select_category')),
        content: Text(l10n.tr('sprite_select_type')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, Meme.typePortrait),
            child: Text(l10n.tr('type_portrait')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, Meme.typeCg),
            child: Text(l10n.tr('type_cg')),
          ),
        ],
      ),
    );
    if (type == null || !ctx.mounted) return;

    // 输入名称
    final name = await showDialog<String>(
      context: ctx,
      builder: (dCtx) {
        final ctrl = TextEditingController(text: result.files.first.name.split('.').first);
        return AlertDialog(
          title: Text(l10n.tr('import_sprite')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.tr('sprite_layers_count')}: ${result.files.length}'),
              Text(l10n.tr('sprite_layer_order_hint'),
                style: TextStyle(fontSize: 12, color: Theme.of(dCtx).colorScheme.outline)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(hintText: l10n.tr('sprite_name_hint')),
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
    if (name == null || name.isEmpty || !ctx.mounted) return;

    try {
      final meme = await prov.importSpriteFromFiles(result.files, name: name, type: type);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('sprite_imported', args: {'count': meme.spriteLayers!.length.toString()}))),
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

  /// 从 krkr pjson + 图片导入立绘/CG
  Future<void> _importSpriteFromPjson(BuildContext ctx, MemeProvider prov) async {
    final l10n = context.read<LocaleProvider>().l10n;
    // 1. 选择 pjson 文件
    final pjsonResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'pjson', 'txt'],
    );
    if (pjsonResult == null || pjsonResult.files.isEmpty) return;
    if (!ctx.mounted) return;

    // 2. 选择图片文件（可多选）
    final imgResult = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    if (imgResult == null || imgResult.files.isEmpty) return;
    if (!ctx.mounted) return;

    // 3. 选择类型
    final type = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('select_category')),
        content: Text(l10n.tr('sprite_select_type')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, Meme.typePortrait),
            child: Text(l10n.tr('type_portrait')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, Meme.typeCg),
            child: Text(l10n.tr('type_cg')),
          ),
        ],
      ),
    );
    if (type == null || !ctx.mounted) return;

    try {
      final meme = await prov.importSpriteFromPjson(
        pjsonResult.files.first,
        imgResult.files,
        type: type,
      );
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('sprite_imported', args: {'count': meme.spriteLayers!.length.toString()}))),
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

  /// 文本/小说编辑弹窗（紧凑弹窗 + 展开按钮）
  void _showTextEditor(BuildContext ctx, MemeProvider prov, {required String type}) {
    showDialog(
      context: ctx,
      builder: (_) => TextEditorScreen(type: type, onSave: (text, title) async {
        await prov.importText(text, name: title, type: type);
      }),
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

/// 自定义背景图：加载图片并应用高斯模糊
class _CustomBackgroundImage extends StatefulWidget {
  final String path;
  final double blur;

  const _CustomBackgroundImage({required this.path, required this.blur});

  @override
  State<_CustomBackgroundImage> createState() => _CustomBackgroundImageState();
}

class _CustomBackgroundImageState extends State<_CustomBackgroundImage> {
  Uint8List? _bytes;
  File? _file;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    if (_loaded) return;
    _loaded = true;
    final storage = context.read<StorageService>();
    if (kIsWeb) {
      storage.readMemeBytes(widget.path).then((b) {
        if (mounted) setState(() => _bytes = b);
      });
    } else {
      final f = storage.getMemeFile(widget.path);
      if (f != null && f.existsSync()) {
        _file = f;
      }
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _bytes != null || _file != null;
    if (!hasData) {
      return const ColoredBox(color: Colors.transparent);
    }

    Widget image = _file != null
        ? Image.file(_file!, fit: BoxFit.cover)
        : Image.memory(_bytes!, fit: BoxFit.cover);

    // 应用高斯模糊
    if (widget.blur > 0) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: widget.blur,
          sigmaY: widget.blur,
        ),
        child: image,
      );
    }

    // 略微放大避免模糊后边缘出现透明边
    return Transform.scale(
      scale: 1.1,
      child: image,
    );
  }
}

/// 满屏 emoji 下雨特效（🥰😍😘）
/// 点击穿透，动画结束后自动关闭
class _EmojiRainOverlay extends StatefulWidget {
  const _EmojiRainOverlay();

  @override
  State<_EmojiRainOverlay> createState() => _EmojiRainOverlayState();
}

class _EmojiRainOverlayState extends State<_EmojiRainOverlay>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<_EmojiParticle> _particles = [];
  static const _emojis = ['🥰', '😍', '😘'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );
    _spawnParticles();
    _controller.forward().then((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _spawnParticles() {
    final rng = Random();
    // 下雨：从顶部下落
    for (int i = 0; i < 36; i++) {
      _particles.add(_EmojiParticle(
        emoji: _emojis[rng.nextInt(_emojis.length)],
        x: rng.nextDouble(),
        delay: rng.nextDouble() * 0.4,
        size: 28.0 + rng.nextDouble() * 28.0,
        rotation: (rng.nextDouble() - 0.5) * 2.0,
        drift: (rng.nextDouble() - 0.5) * 0.25,
        speed: 0.8 + rng.nextDouble() * 0.4,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // IgnorePointer 让点击穿透，粒子不影响下方操作
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (ctx, _) {
            return Stack(
              children: _particles.map((p) {
                double t = (_controller.value - p.delay) * p.speed;
                if (t <= 0) return const SizedBox.shrink();
                if (t > 1) t = 1;
                final y = -60.0 + t * (size.height + 120);
                final x = p.x * size.width + p.drift * size.width * t;
                final opacity = t < 0.08
                    ? t / 0.08
                    : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
                final angle = p.rotation * t * pi * 2;
                return Positioned(
                  left: x,
                  top: y,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: angle,
                      child: Text(
                        p.emoji,
                        style: TextStyle(
                          fontSize: p.size,
                          decoration: TextDecoration.none,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _EmojiParticle {
  final String emoji;
  final double x; // 起始水平位置 0..1
  final double delay; // 起始延迟
  final double size;
  final double rotation;
  final double drift; // 水平漂移系数
  final double speed; // 下落速度倍率
  _EmojiParticle({
    required this.emoji,
    required this.x,
    required this.delay,
    required this.size,
    required this.rotation,
    required this.drift,
    required this.speed,
  });
}
