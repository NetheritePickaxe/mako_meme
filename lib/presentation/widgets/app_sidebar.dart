import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sticker_providers.dart';
import '../../data/database/database.dart';

/// 侧边栏：展示命名空间列表
class AppSidebar extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;

  const AppSidebar({
    super.key,
    required this.isOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nsAsync = ref.watch(allNamespacesProvider);
    final activeNs = ref.watch(activeNamespaceProvider);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: isOpen ? 260 : 0,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: isOpen
          ? Column(
              children: [
                _Header(onClose: onClose),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _NsTile(
                        label: '全部表情包',
                        icon: Icons.folder_special,
                        isActive: activeNs == null,
                        onTap: () {
                          ref.read(activeNamespaceProvider.notifier).state = null;
                        },
                      ),
                      const Divider(height: 8),
                      nsAsync.when(
                        loading: () => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        error: (e, _) =>
                            Center(child: Text('加载失败', style: theme.textTheme.bodySmall)),
                        data: (nsList) => Column(
                          children: [
                            ...nsList.map((ns) => _NsTile(
                                  label: ns.name,
                                  icon: Icons.folder,
                                  color: ns.color != null
                                      ? Color(int.parse(ns.color!, radix: 16))
                                      : null,
                                  isActive: activeNs == ns.id,
                                  onTap: () {
                                    ref.read(activeNamespaceProvider.notifier).state =
                                        ns.id;
                                  },
                                  onDelete: () => _deleteNs(context, ref, ns),
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _AddNamespaceButton(),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  void _deleteNs(BuildContext context, WidgetRef ref, NamespaceData ns) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除命名空间'),
        content: Text('删除「${ns.name}」后，其中的表情包将变为未分类。确定要删除吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      final repo = ref.read(stickerRepositoryProvider);
      await repo.deleteNamespace(ns.id);
      if (ref.read(activeNamespaceProvider) == ns.id) {
        ref.read(activeNamespaceProvider.notifier).state = null;
      }
    }
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Text('命名空间',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onClose,
            tooltip: '收起侧边栏',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _NsTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _NsTile({
    required this.label,
    required this.icon,
    this.color,
    this.isActive = false,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fgColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isActive
            ? theme.colorScheme.primaryContainer.withAlpha(100)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color ?? fgColor, size: 20),
          title: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: fgColor)),
          trailing: onDelete != null
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                )
              : null,
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _AddNamespaceButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: OutlinedButton.icon(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('新建命名空间'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建命名空间'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '例如：工作、生活、搞笑',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              final repo = ref.read(stickerRepositoryProvider);
              await repo.createNamespace(name: name);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}
