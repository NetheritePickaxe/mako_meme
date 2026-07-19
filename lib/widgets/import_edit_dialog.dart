import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/l10n.dart';
import '../services/storage_service.dart';

/// 导入时编辑对话框
///
/// 用于在导入图片完成后，逐张让用户重命名、打标签、选文件夹、收藏、删除。
/// 切换到下一张时自动保存当前编辑；点击完成或返回键时保存当前页并退出。
class ImportEditDialog extends StatefulWidget {
  final List<Meme> memes;

  const ImportEditDialog({super.key, required this.memes});

  /// 弹出导入时编辑对话框，逐张编辑给定的 memes
  static Future<void> show(BuildContext context, List<Meme> memes) {
    if (memes.isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportEditDialog(memes: memes),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<ImportEditDialog> createState() => _ImportEditDialogState();
}

class _ImportEditDialogState extends State<ImportEditDialog> {
  late int _index = 0;
  // 当前 meme 的可编辑状态
  late TextEditingController _nameCtrl;
  late TextEditingController _tagCtrl;
  List<String> _tags = [];
  String? _folderId;
  bool _isFavorite = false;
  bool _deleted = false;

  // 图片预览字节（web）/ File（native）
  Uint8List? _bytes;
  File? _file;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _tagCtrl = TextEditingController();
    _loadCurrent();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Meme get _current => widget.memes[_index];

  /// 加载当前 meme 的状态：名称、标签、文件夹、收藏、图片字节
  void _loadCurrent() {
    final m = _current;
    _nameCtrl.text = m.name;
    _tagCtrl.text = '';
    _tags = List<String>.from(m.tags);
    _folderId = m.folderId;
    _isFavorite = m.isFavorite;
    _deleted = false;
    _bytes = null;
    _file = null;
    _loading = true;
    _loadImageBytes();
  }

  Future<void> _loadImageBytes() async {
    final m = _current;
    if (!m.isImageType || m.displayPath.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    try {
      final storage = context.read<StorageService>();
      if (kIsWeb) {
        final b = await storage.readMemeBytes(m.displayPath);
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
      } else {
        final f = storage.getMemeFile(m.displayPath);
        if (mounted) {
          setState(() {
            _file = f;
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 保存当前编辑到 provider（除非已标记删除）
  Future<void> _saveCurrent() async {
    if (_deleted) return;
    final m = _current;
    final prov = context.read<MemeProvider>();
    final newName = _nameCtrl.text.trim();
    if (newName.isNotEmpty && newName != m.name) {
      await prov.renameMeme(m.id, newName);
    }
    // 同步标签：先移除原标签中没有的，再添加新标签中没有的
    final oldTags = m.tags.toSet();
    final newTags = _tags.toSet();
    for (final t in oldTags.difference(newTags)) {
      await prov.removeTag(m.id, t);
    }
    for (final t in newTags.difference(oldTags)) {
      await prov.addTag(m.id, t);
    }
    // 同步文件夹
    if (_folderId != m.folderId) {
      await prov.moveToFolder(m.id, _folderId);
    }
    // 同步收藏
    if (_isFavorite != m.isFavorite) {
      await prov.toggleFavorite(m.id);
    }
  }

  /// 删除当前 meme
  Future<void> _deleteCurrent() async {
    final prov = context.read<MemeProvider>();
    await prov.deleteMeme(_current.id);
    setState(() => _deleted = true);
  }

  /// 切换到下一张（保存当前）
  Future<void> _goNext() async {
    await _saveCurrent();
    if (!mounted) return;
    if (_index < widget.memes.length - 1) {
      setState(() {
        _index++;
        _loadCurrent();
      });
    }
  }

  /// 切换到上一张（保存当前）
  Future<void> _goPrev() async {
    await _saveCurrent();
    if (!mounted) return;
    if (_index > 0) {
      setState(() {
        _index--;
        _loadCurrent();
      });
    }
  }

  /// 完成编辑：保存当前并退出
  Future<void> _finish() async {
    await _saveCurrent();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _addTag() {
    final t = _tagCtrl.text.trim();
    if (t.isEmpty || _tags.contains(t)) {
      _tagCtrl.clear();
      return;
    }
    setState(() {
      _tags.add(t);
      _tagCtrl.clear();
    });
  }

  void _removeTag(String t) {
    setState(() => _tags.remove(t));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.watch<LocaleProvider>().l10n;
    final prov = context.watch<MemeProvider>();
    final folders = prov.folders;
    final isLast = _index >= widget.memes.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.tr('close'),
            onPressed: _finish,
          ),
          title: Text(
            l10n.tr('import_edit_title', args: {
              'index': (_index + 1).toString(),
              'total': widget.memes.length.toString(),
            }),
          ),
          actions: [
            TextButton(
              onPressed: _finish,
              child: Text(l10n.tr('finish')),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 图片预览区
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: _buildPreview(theme),
                ),
              ),
              // 编辑表单
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 名称
                      TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('meme_name'),
                          prefixIcon: const Icon(Icons.title, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 标签
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.tr('add_tag'),
                                prefixIcon: const Icon(Icons.tag, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addTag(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add),
                            onPressed: _addTag,
                          ),
                        ],
                      ),
                      if (_tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _tags.map((t) => InputChip(
                            label: Text(t),
                            onDeleted: () => _removeTag(t),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // 文件夹选择
                      DropdownButtonFormField<String?>(
                        key: ValueKey('folder-$_folderId-${_current.id}'),
                        initialValue: _folderId,
                        decoration: InputDecoration(
                          labelText: l10n.tr('folder'),
                          prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(l10n.tr('no_folder')),
                          ),
                          ...folders.map((f) => DropdownMenuItem<String?>(
                            value: f.id,
                            child: Text(f.name, overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) => setState(() => _folderId = v),
                      ),
                      const SizedBox(height: 12),
                      // 收藏 + 删除
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              value: _isFavorite,
                              onChanged: (v) => setState(() => _isFavorite = v ?? false),
                              title: Text(l10n.tr('favorite')),
                              secondary: Icon(
                                _isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: _isFavorite ? Colors.red : null,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 删除按钮
                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await _confirmDelete(l10n);
                          if (confirmed != true) return;
                          await _deleteCurrent();
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: Text(l10n.tr('delete'), style: const TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 底部导航：上一张 / 下一张
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _index > 0 ? _goPrev : null,
                      icon: const Icon(Icons.chevron_left),
                      label: Text(l10n.tr('previous')),
                    ),
                    const Spacer(),
                    if (_deleted)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          l10n.tr('deleted_hint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (isLast)
                      FilledButton.icon(
                        onPressed: _finish,
                        icon: const Icon(Icons.check),
                        label: Text(l10n.tr('finish')),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _goNext,
                        icon: const Icon(Icons.chevron_right),
                        label: Text(l10n.tr('next')),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_deleted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              context.read<LocaleProvider>().l10n.tr('deleted_hint'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
      );
    }
    final m = _current;
    // PDF / 非图片
    if (!m.isImageType) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(m.name, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    // SVG
    if (m.isVector) {
      final svgBytes = _bytes ?? _file?.readAsBytesSync();
      if (svgBytes != null) {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: SvgPicture.memory(svgBytes, fit: BoxFit.contain),
        );
      }
    }
    // 普通位图
    if (_file != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 6.0,
        child: Image.file(_file!, fit: BoxFit.contain, errorBuilder: (_, _, _) => _placeholder(theme)),
      );
    }
    if (_bytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 6.0,
        child: Image.memory(_bytes!, fit: BoxFit.contain, errorBuilder: (_, _, _) => _placeholder(theme)),
      );
    }
    return _placeholder(theme);
  }

  Widget _placeholder(ThemeData theme) => Center(
    child: Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.outline),
  );

  Future<bool?> _confirmDelete(L10n l10n) {
    final m = _current;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('delete')),
        content: Text(l10n.tr('delete_confirm', args: {'name': m.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.tr('delete')),
          ),
        ],
      ),
    );
  }
}
