import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/phantom_tank_batch_screen.dart';
import '../services/image_tool_service.dart';
import '../services/storage_service.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          // 右侧操作按钮：窄屏可横向滚动，删除固定在最后
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (prov.selected.isNotEmpty) ...[
                    // 系统图集分类为只读：仅允许导出/分享，不显示移动/分类/删除
                    if (!prov.typeFilter.contains(Meme.typeSystemGallery)) ...[
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
                    ],
                    IconButton(
                      icon: const Icon(Icons.ios_share, size: 20),
                      tooltip: l10n.tr('export_selected'),
                      onPressed: () => _exportSelected(context, prov, l10n),
                    ),
                    if (!prov.typeFilter.contains(Meme.typeSystemGallery))
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        tooltip: l10n.tr('delete_selected'),
                        onPressed: () => _confirmDelete(context, prov, l10n),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图片工具底部菜单：格式转换 / 尺寸修改 / 转GIF-APNG / 幻影坦克
  /// 未选图片时也允许打开菜单查看可用工具（所有项全灰、不可点）
  static void showToolsMenu(BuildContext ctx, MemeProvider prov, L10n l10n) {
    final selected = prov.selectedMemes;
    final canAnimate = selected.length >= 2;
    // 仅对可处理的图片类型生效（排除矢量图/PSD/PDF 等需特殊解码的）
    final imageMemes = selected.where((m) =>
        m.isImageType && !m.isVector && !m.isPsd && !m.isPdf).toList();
    // 幻影坦克专用：仅接受 image/emoji 类型，再排除动图（GIF/APNG）
    final phantomEligible = selected.where((m) =>
        m.type == Meme.typeImage || m.type == Meme.typeEmoji).toList();
    final staticImageMemes = phantomEligible.where((m) => !m.isAnimated).toList();
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
              onTap: imageMemes.isEmpty ? null : () {
                Navigator.pop(bCtx);
                _showConvertDialog(ctx, prov, l10n, imageMemes);
              },
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio),
              title: Text(l10n.tr('tool_resize')),
              enabled: imageMemes.isNotEmpty,
              onTap: imageMemes.isEmpty ? null : () {
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
            ListTile(
              leading: const Icon(Icons.visibility),
              title: Text(l10n.tr('tool_phantom_tank')),
              // 幻影坦克仅支持静态图片/表情，过滤掉 GIF/APNG 等动图及文字/md/pdf 等
              enabled: staticImageMemes.length >= 2,
              subtitle: staticImageMemes.length < 2 ? Text(l10n.tr('phantom_need_two_static')) : null,
              onTap: staticImageMemes.length >= 2 ? () {
                Navigator.pop(bCtx);
                if (staticImageMemes.length == 2) {
                  _showPhantomTankDialog(ctx, prov, l10n, staticImageMemes);
                } else {
                  // 3+ 张进入批量生成独立界面
                  Navigator.push(ctx, MaterialPageRoute(
                    builder: (_) => PhantomTankBatchScreen(memes: staticImageMemes),
                  ));
                }
              } : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 批量格式转换
  static void _showConvertDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
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

  static Future<void> _batchConvert(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes, String format, int quality) async {
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
  static void _showResizeDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
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

  static Future<void> _batchResize(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes, double ratio) async {
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
  static void _showAnimationDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
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

  static Future<void> _makeAnimation(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes, int frameDuration, String format) async {
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

  /// 幻影坦克制作对话框
  static void _showPhantomTankDialog(BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes) {
    bool swapFgBg = false; // false: 第一张为前景
    bool colorMode = true;
    double brightnessRatio = 1.0;
    double colorIntensity = 1.0;
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (sCtx, setState) => AlertDialog(
          title: Text(l10n.tr('tool_phantom_tank')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 前景/背景预览
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(l10n.tr('phantom_foreground'),
                            style: TextStyle(fontSize: 11, color: Theme.of(sCtx).colorScheme.primary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          _ptThumb(sCtx, memes[swapFgBg ? 1 : 0]),
                          Text(memes[swapFgBg ? 1 : 0].name,
                            style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      tooltip: l10n.tr('phantom_swap'),
                      onPressed: () => setState(() => swapFgBg = !swapFgBg),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(l10n.tr('phantom_background'),
                            style: TextStyle(fontSize: 11, color: Theme.of(sCtx).colorScheme.outline, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          _ptThumb(sCtx, memes[swapFgBg ? 0 : 1]),
                          Text(memes[swapFgBg ? 0 : 1].name,
                            style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 彩色/黑白切换
                Row(children: [
                  ChoiceChip(
                    label: Text(l10n.tr('phantom_color')),
                    selected: colorMode,
                    onSelected: (_) => setState(() => colorMode = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(l10n.tr('phantom_bw')),
                    selected: !colorMode,
                    onSelected: (_) => setState(() => colorMode = false),
                  ),
                ]),
                const SizedBox(height: 12),
                // 亮度比例
                Text('${l10n.tr('phantom_brightness')}: ${brightnessRatio.toStringAsFixed(2)}'),
                Slider(
                  value: brightnessRatio,
                  min: 0.5, max: 2.0, divisions: 30,
                  label: brightnessRatio.toStringAsFixed(2),
                  onChanged: (v) => setState(() => brightnessRatio = v),
                ),
                // 色彩强度（仅彩色模式）
                if (colorMode) ...[
                  Text('${l10n.tr('phantom_color_intensity')}: ${colorIntensity.toStringAsFixed(2)}'),
                  Slider(
                    value: colorIntensity,
                    min: 0.0, max: 1.0, divisions: 20,
                    label: colorIntensity.toStringAsFixed(2),
                    onChanged: (v) => setState(() => colorIntensity = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _makePhantomTank(ctx, prov, l10n, memes, swapFgBg, colorMode, brightnessRatio, colorIntensity);
              },
              child: Text(l10n.tr('phantom_generate')),
            ),
          ],
        ),
      ),
    );
  }

  /// 幻影坦克缩略图
  static Widget _ptThumb(BuildContext ctx, Meme m) {
    final storage = ctx.read<StorageService>();
    return FutureBuilder<Uint8List?>(
      future: storage.readMemeBytes(m.filePath),
      builder: (_, snap) {
        if (snap.data == null) {
          return Container(width: 64, height: 64, color: Theme.of(ctx).colorScheme.surfaceContainerHigh);
        }
        return Image.memory(snap.data!, width: 64, height: 64, fit: BoxFit.cover);
      },
    );
  }

  static Future<void> _makePhantomTank(
    BuildContext ctx, MemeProvider prov, L10n l10n, List<Meme> memes,
    bool swapFgBg, bool colorMode, double brightnessRatio, double colorIntensity,
  ) async {
    final tool = ctx.read<ImageToolService>();
    final messenger = ScaffoldMessenger.of(ctx);
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(width: 16),
          Expanded(child: Text('${l10n.tr('phantom_generating')}…')),
        ]),
      ),
    );
    try {
      final fg = memes[swapFgBg ? 1 : 0];
      final bg = memes[swapFgBg ? 0 : 1];
      await tool.makePhantomTank(
        fg.filePath, bg.filePath,
        colorMode: colorMode,
        brightnessRatio: brightnessRatio,
        colorIntensity: colorIntensity,
        name: '${fg.name}_phantom',
      );
      await prov.loadAll();
      if (ctx.mounted) {
        Navigator.pop(ctx);
        messenger.showSnackBar(SnackBar(content: Text(l10n.tr('phantom_success'))));
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
    final settings = ctx.read<SettingsProvider>();
    final allTypes = [
      {'type': Meme.typeEmoji, 'label': l10n.tr('type_emoji'), 'icon': Icons.emoji_emotions_outlined},
      {'type': Meme.typeGif, 'label': l10n.tr('type_gif'), 'icon': Icons.animation},
      {'type': Meme.typeImage, 'label': l10n.tr('type_image'), 'icon': Icons.image_outlined},
      {'type': Meme.typeText, 'label': l10n.tr('type_text'), 'icon': Icons.text_fields},
      {'type': Meme.typePortrait, 'label': l10n.tr('type_portrait'), 'icon': Icons.accessibility_new},
      {'type': Meme.typeCg, 'label': l10n.tr('type_cg'), 'icon': Icons.wallpaper_outlined},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('type_character_card'), 'icon': Icons.contact_page_outlined},
      {'type': Meme.typeVector, 'label': l10n.tr('type_vector'), 'icon': Icons.polyline_outlined},
      {'type': Meme.typePsd, 'label': l10n.tr('type_psd'), 'icon': Icons.layers_outlined},
      {'type': Meme.typeManga, 'label': l10n.tr('type_manga'), 'icon': Icons.menu_book_outlined},
      {'type': Meme.typeFile, 'label': l10n.tr('type_file'), 'icon': Icons.folder_outlined},
    ];
    final types = allTypes.where((t) => settings.isCategoryVisible(t['type'] as String)).toList();

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
