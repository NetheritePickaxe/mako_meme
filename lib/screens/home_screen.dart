import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../providers/meme_provider.dart';
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

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '打开菜单',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(_getTitle(prov)),
        actions: [
          IconButton(
            icon: Icon(prov.isMulti ? Icons.close : Icons.checklist),
            tooltip: prov.isMulti ? '退出多选' : '多选',
            onPressed: () => prov.toggleMulti(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: (v) {
              switch (v) {
                case 'date': prov.setSort(SortBy.date); break;
                case 'name': prov.setSort(SortBy.name); break;
                case 'size': prov.setSort(SortBy.size); break;
                case 'order': prov.toggleOrder(); break;
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'date', checked: prov.sortBy == SortBy.date, child: const Text('按日期')),
              CheckedPopupMenuItem(value: 'name', checked: prov.sortBy == SortBy.name, child: const Text('按名称')),
              CheckedPopupMenuItem(value: 'size', checked: prov.sortBy == SortBy.size, child: const Text('按大小')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'order', child: Text(prov.order == SortOrder.asc ? '↑ 升序' : '↓ 降序')),
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
                SnackBar(content: Text('导入了 ${files.length} 张图片'), duration: const Duration(seconds: 2)),
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
                  if (prov.tagFilter.isNotEmpty) _buildTagChips(prov),
                  Expanded(
                    child: _buildMixedGrid(prov),
                  ),
                ],
              ),
              if (_dragOver)
                Positioned.fill(
                  child: Container(
                    color: Colors.black45,  // 半透明黑底，总是清晰
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
                            Text('释放以导入图片', style: TextStyle(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showImportMenu(context, prov),
        icon: const Icon(Icons.add),
        label: const Text('导入'),
      ),
    );
  }

  /// 混合网格：文件夹 + 表情包卡片
  Widget _buildMixedGrid(MemeProvider prov) {
    // 如果已选中文件夹或场景，只显示表情
    if (prov.folderId != null || prov.moodFilter != null) {
      return MemeGrid(memes: prov.memes);
    }

    // 显示文件夹 + 未分类的表情
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
            // 未分类的表情作为普通 MemeCard 展示
            final meme = uncategorized[i - folders.length];
            return _buildMemeCardInGrid(meme);
          },
        );
      },
    );
  }

  Widget _buildMemeCardInGrid(Meme meme) {
    // 使用简单的 Image.memory 预览
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
                  Text('丢失', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
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

  String _getTitle(MemeProvider prov) {
    if (prov.isMulti) return '已选 ${prov.selected.length} 项';
    if (prov.moodFilter != null) {
      final m = findMoodById(prov.moodFilter);
      return m != null ? '${m.name} 场景' : 'Mako Meme';
    }
    if (prov.folderId == null) return 'Mako Meme';
    return prov.folders.where((f) => f.id == prov.folderId).firstOrNull?.name ?? 'Mako Meme';
  }

  Widget _buildDrawer(BuildContext context, MemeProvider prov) {
    final theme = Theme.of(context);
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
                  Text('共 ${prov.allMemesCount} 个表情', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerItem(
                    icon: Icons.all_inbox,
                    label: '全部表情',
                    count: prov.allMemesCount,
                    isActive: prov.folderId == null && prov.moodFilter == null,
                    onTap: () { prov.selectFolder(null); prov.clearMood(); Navigator.pop(context); },
                  ),
                  _drawerItem(
                    icon: Icons.favorite,
                    label: '收藏',
                    count: prov.favorites.length,
                    isActive: false,
                    onTap: () { prov.selectMood(null); Navigator.pop(context); },
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  // 情绪/场景分类
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('场景', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withAlpha(120))),
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
                    child: Text('文件夹', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withAlpha(120))),
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
                    title: const Text('设置'),
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
            // 新建文件夹按钮
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () => _showCreateFolderDialog(context, prov),
                icon: const Icon(Icons.create_new_folder, size: 18),
                label: const Text('新建文件夹'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
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

  Widget _buildTagChips(MemeProvider prov) {
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
        ],
      ),
    );
  }

  void _showImportMenu(BuildContext ctx, MemeProvider prov) {
    showModalBottomSheet(
      context: ctx,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('导入图片'),
              subtitle: const Text('JPG / PNG / GIF / WebP / BMP'),
              onTap: () { Navigator.pop(bCtx); _importFiles(ctx, prov); },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('导入文字 / Emoji'),
              subtitle: const Text('纯文本或 Emoji 符号'),
              onTap: () { Navigator.pop(bCtx); _importText(ctx, prov); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导入备份'),
              subtitle: const Text('ZIP 备份 / 图片包'),
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
    final ctrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('导入文字 / Emoji'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '输入文字或 Emoji...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              prov.importText(ctrl.text.trim());
              Navigator.pop(dCtx);
            }
          }, child: const Text('导入')),
        ],
      ),
    );
  }

  Future<void> _importZip(BuildContext ctx) async {
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
        title: const Text('导入备份'),
        content: Text('是否从 ${zipFile.name} 导入？\n\n如果 ZIP 包含 memes.json，将覆盖当前所有数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('导入')),
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
        msg = '备份导入成功';
      } else if (count > 0) {
        msg = '导入了 $count 张图片';
      } else {
        msg = '导入失败：无法识别的 ZIP 文件';
      }
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showCreateFolderDialog(BuildContext ctx, MemeProvider prov) {
    final ctrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              prov.createFolder(ctrl.text.trim());
              Navigator.pop(dCtx);
            }
          }, child: const Text('创建')),
        ],
      ),
    );
  }

  void _showFolderMenu(BuildContext ctx, MemeProvider prov, MemeFolder folder) {
    showModalBottomSheet(
      context: ctx,
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () { Navigator.pop(bCtx); _renameFolder(ctx, prov, folder); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(bCtx);
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('删除文件夹'),
                    content: Text('删除「${folder.name}」后，其中的表情不会删除，但会变为未分类。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('删除')),
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
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          FilledButton(onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              prov.renameFolder(folder.id, ctrl.text.trim());
              Navigator.pop(dCtx);
            }
          }, child: const Text('保存')),
        ],
      ),
    );
  }
}
