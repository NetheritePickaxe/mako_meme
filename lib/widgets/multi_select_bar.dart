import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/image_tool_service.dart';
import '../l10n/l10n.dart';

class MultiSelectBar extends StatelessWidget {
  const MultiSelectBar({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.select_all, size: 18),
            label: Text(l10n.tr('select_all')),
            onPressed: () => prov.selectAll(),
          ),
          TextButton.icon(
            icon: const Icon(Icons.deselect, size: 18),
            label: Text(l10n.tr('cancel')),
            onPressed: () => prov.deselectAll(),
          ),
          const Spacer(),
          if (prov.selected.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.build_outlined, size: 20),
              tooltip: l10n.tr('tools'),
              onPressed: () => _showToolsMenu(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open, size: 20),
              tooltip: l10n.tr('move_to_folder'),
              onPressed: () => _showMoveDialog(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.label_outline, size: 20),
              tooltip: l10n.tr('change_category'),
              onPressed: () => _showTypeDialog(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share, size: 20),
              tooltip: l10n.tr('export_selected'),
              onPressed: () => _exportSelected(context, prov, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: l10n.tr('delete_selected'),
              onPressed: () => _confirmDelete(context, prov, l10n),
            ),
          ],
        ],
      ),
    );
  }

  /// 图片工具底部菜单：格式转换 / 尺寸修改 / 转GIF-APNG
  void _showToolsMenu(BuildContext ctx, MemeProvider prov, L10n l10n) {
    final selected = prov.selectedMemes;
    final canAnimate = selected.length >= 2;
    // 仅对可处理的图片类型生效
    final imageMemes = selected.where((m) =>
        m.isImageType && !m.isVector && !m.isPsd && !m.isPdf).toList();
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${l10n.tr('tools')} · ${selected.length} ${l10n.tr('items_count')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.tr('tool_convert')),
              subtitle: Text(l10n.tr('convert')),
              enabled: imageMemes.isNotEmpty,
              onTap: () {
                Navigator.pop(bCtx);
                _showConvertDialog(ctx, prov, l10n, imageMemes);
              },
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio),
              title: Text(l10n.tr('tool_resize')),
              enabled: imageMemes.isNotEmpty,
              onTap: () {
                Navigator.pop(bCtx);
                _showResizeDialog(ctx, prov, l10n, imageMemes);
              },
            ),
            ListTile(
              leading: const Icon(Icons.animation),
              title: Text(l10n.tr('tool_to_gif')),
              enabled: canAnimate,
              subtitle: !canAnimate ? Text(l10n.tr('sprite_need_multiple')) : null,
              onTap: canAnimate ? () {
                Navigator.pop(bCtx);
                _showAnimationDialog(ctx, prov, l10n, imageMemes);
              } : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 批量格式转换
  void _showConvertDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
    String format = 'png';
    int quality = 90;
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (sCtx, setState) => AlertDialog(
          title: Text(l10n.tr('tool_convert')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.tr('selected_count')}: ${memes.length}'),
              const SizedBox(height: 12),
              Text(l10n.tr('output_format')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ImageToolService.outputFormats.map((f) {
                  return ChoiceChip(
                    label: Text(f.toUpperCase()),
                    selected: format == f,
                    onSelected: (_) => setState(() => format = f),
                  );
                }).toList(),
              ),
              if (format == 'jpg') ...[
                const SizedBox(height: 12),
                Text('${l10n.tr('quality')}: $quality'),
                Slider(
                  value: quality.toDouble(),
                  min: 10, max: 100, divisions: 18,
                  onChanged: (v) => setState(() => quality = v.round()),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _batchConvert(ctx, prov, l10n, memes, format, quality);
              },
              child: Text(l10n.tr('convert')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchConvert(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes, String format, int quality) async {
    final tool = ctx.read<ImageToolService>();
    final messenger = ScaffoldMessenger.of(ctx);
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(width: 16),
          Expanded(child: Text('${l10n.tr('converting')}…')),
        ]),
      ),
    );
    int ok = 0;
    for (final m in memes) {
      try {
        await tool.convertFormat(m.filePath, format, quality: quality, name: m.name);
        ok++;
      } catch (_) {}
    }
    await prov.loadAll();
    if (ctx.mounted) {
      Navigator.pop(ctx);
      messenger.showSnackBar(SnackBar(content: Text('$ok / ${memes.length} ${l10n.tr('convert_success')}')));
    }
  }

  /// 批量尺寸修改
  void _showResizeDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
    int percent = 50;
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (sCtx, setState) => AlertDialog(
          title: Text(l10n.tr('tool_resize')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.tr('selected_count')}: ${memes.length}'),
              const SizedBox(height: 12),
              Text('${l10n.tr('scale')}: $percent%'),
              Slider(
                value: percent.toDouble(),
                min: 10, max: 200, divisions: 19,
                label: '$percent%',
                onChanged: (v) => setState(() => percent = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _batchResize(ctx, prov, l10n, memes, percent / 100.0);
              },
              child: Text(l10n.tr('resize')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchResize(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes, double ratio) async {
    final tool = ctx.read<ImageToolService>();
    final messenger = ScaffoldMessenger.of(ctx);
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(width: 16),
          Expanded(child: Text('${l10n.tr('resizing')}…')),
        ]),
      ),
    );
    int ok = 0;
    for (final m in memes) {
      try {
        await tool.resize(m.filePath, percent: ratio, name: m.name);
        ok++;
      } catch (_) {}
    }
    await prov.loadAll();
    if (ctx.mounted) {
      Navigator.pop(ctx);
      messenger.showSnackBar(SnackBar(content: Text('$ok / ${memes.length} ${l10n.tr('resize_success')}')));
    }
  }

  /// 多图转 GIF/APNG
  void _showAnimationDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
    int frameDuration = 200;
    String format = 'gif';
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (sCtx, setState) => AlertDialog(
          title: Text(l10n.tr('tool_to_gif')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.tr('selected_count')}: ${memes.length}'),
              const SizedBox(height: 12),
              Text('${l10n.tr('frame_duration')}: ${frameDuration}ms'),
              Slider(
                value: frameDuration.toDouble(),
                min: 50, max: 1000, divisions: 19,
                label: '${frameDuration}ms',
                onChanged: (v) => setState(() => frameDuration = v.round()),
              ),
              const SizedBox(height: 8),
              Row(children: [
                ChoiceChip(label: const Text('GIF'), selected: format == 'gif', onSelected: (_) => setState(() => format = 'gif')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('APNG'), selected: format == 'apng', onSelected: (_) => setState(() => format = 'apng')),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _makeAnimation(ctx, prov, l10n, memes, frameDuration, format);
              },
              child: Text(l10n.tr(format == 'gif' ? 'make_gif' : 'make_apng')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makeAnimation(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes, int frameDuration, String format) async {
    final tool = ctx.read<ImageToolService>();
    final messenger = ScaffoldMessenger.of(ctx);
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(width: 16),
          Expanded(child: Text('${l10n.tr('converting')}…')),
        ]),
      ),
    );
    try {
      final paths = memes.map((m) => m.filePath).toList();
      if (format == 'gif') {
        await tool.imagesToGif(paths, frameDurationMs: frameDuration);
      } else {
        await tool.imagesToApng(paths, frameDurationMs: frameDuration);
      }
      await prov.loadAll();
      if (ctx.mounted) {
        Navigator.pop(ctx);
        messenger.showSnackBar(SnackBar(content: Text(l10n.tr('convert_success'))));
      }
    } catch (e) {
      if (ctx.mounted) {
        Navigator.pop(ctx);
        messenger.showSnackBar(SnackBar(content: Text('${l10n.tr('convert_failed')}: $e')));
      }
    }
  }

  void _showMoveDialog(BuildContext ctx, MemeProvider prov, L10n l10n) {
    showDialog(
      context: ctx,
      builder: (dCtx) => SimpleDialog(
        title: Text(l10n.tr('move_to_folder')),
        children: [
          SimpleDialogOption(
            onPressed: () { prov.moveSelectedToFolder(null); Navigator.pop(dCtx); },
            child: Text(l10n.tr('all_folders')),
          ),
          ...prov.folders.map((f) => SimpleDialogOption(
            onPressed: () { prov.moveSelectedToFolder(f.id); Navigator.pop(dCtx); },
            child: Text(f.name),
          )),
        ],
      ),
    );
  }

  void _showTypeDialog(BuildContext ctx, MemeProvider prov, L10n l10n) {
    final types = [
      {'type': Meme.typeEmoji, 'label': l10n.tr('type_emoji'), 'icon': Icons.face},
      {'type': Meme.typeGif, 'label': l10n.tr('type_gif'), 'icon': Icons.gif},
      {'type': Meme.typeImage, 'label': l10n.tr('type_image'), 'icon': Icons.image},
      {'type': Meme.typeText, 'label': l10n.tr('type_text'), 'icon': Icons.text_fields},
      {'type': Meme.typePortrait, 'label': l10n.tr('type_portrait'), 'icon': Icons.portrait},
      {'type': Meme.typeCg, 'label': l10n.tr('type_cg'), 'icon': Icons.photo_library},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('type_character_card'), 'icon': Icons.person_outline},
    ];

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('change_category')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: types.map((t) {
            final type = t['type'] as String;
            final label = t['label'] as String;
            final icon = t['icon'] as IconData;
            return ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () {
                prov.setSelectedType(type);
                Navigator.pop(dCtx);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
        ],
      ),
    );
  }

  Future<void> _exportSelected(BuildContext ctx, MemeProvider prov, L10n l10n) async {
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l10n.tr('selected_memes', args: {'count': prov.selected.length.toString()}))),
      );
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(l10n.tr('operation_failed', args: {'error': e.toString()}))),
        );
      }
    }
  }

  void _confirmDelete(BuildContext ctx, MemeProvider prov, L10n l10n) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('delete_meme_title')),
        content: Text(l10n.tr('delete_selected_confirm', args: {'count': prov.selected.length.toString()})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(l10n.tr('delete'))),
        ],
      ),
    );
    if (confirm == true) await prov.deleteSelected();
  }
}
