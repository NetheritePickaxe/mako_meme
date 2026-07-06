import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/meme_provider.dart';

class MultiSelectBar extends StatelessWidget {
  const MultiSelectBar({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.select_all, size: 18),
            label: const Text('全选'),
            onPressed: () => prov.selectAll(),
          ),
          TextButton.icon(
            icon: const Icon(Icons.deselect, size: 18),
            label: const Text('取消'),
            onPressed: () => prov.deselectAll(),
          ),
          const Spacer(),
          if (prov.selected.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.folder_open, size: 20),
              tooltip: '移动到文件夹',
              onPressed: () => _showMoveDialog(context, prov),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share, size: 20),
              tooltip: '导出选中',
              onPressed: () => _exportSelected(context, prov),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: '删除选中',
              onPressed: () => _confirmDelete(context, prov),
            ),
          ],
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext ctx, MemeProvider prov) {
    showDialog(
      context: ctx,
      builder: (dCtx) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          SimpleDialogOption(
            onPressed: () { prov.moveSelectedToFolder(null); Navigator.pop(dCtx); },
            child: const Text('未分类'),
          ),
          ...prov.folders.map((f) => SimpleDialogOption(
            onPressed: () { prov.moveSelectedToFolder(f.id); Navigator.pop(dCtx); },
            child: Text(f.name),
          )),
        ],
      ),
    );
  }

  Future<void> _exportSelected(BuildContext ctx, MemeProvider prov) async {
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('已选中 ${prov.selected.length} 个表情')),
      );
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext ctx, MemeProvider prov) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('删除表情'),
        content: Text('确定删除选中的 ${prov.selected.length} 张表情？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) await prov.deleteSelected();
  }
}
