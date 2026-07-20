import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/image_tool_service.dart';
import '../services/storage_service.dart';
import '../l10n/l10n.dart';

/// 一对前景-隐藏配对
class _Pair {
  Meme foreground;
  Meme hidden;
  _Pair({required this.foreground, required this.hidden});
}

/// 批量幻影坦克生成界面
///
/// 支持多对一一对应配对：
/// - 用户可添加多个「前景图 + 隐藏图」配对
/// - 每对生成一张幻影坦克
/// - 支持批量添加多张前景图，自动与剩余图片按顺序配对
/// - 合成参数（彩色/黑白、亮度比例、色彩强度）对所有生成共享
class PhantomTankBatchScreen extends StatefulWidget {
  /// 预选的图片列表，作为可配对资源池
  final List<Meme> memes;

  const PhantomTankBatchScreen({super.key, required this.memes});

  @override
  State<PhantomTankBatchScreen> createState() => _PhantomTankBatchScreenState();
}

class _PhantomTankBatchScreenState extends State<PhantomTankBatchScreen> {
  final List<_Pair> _pairs = [];
  bool _colorMode = true;
  double _brightnessRatio = 1.0;
  double _colorIntensity = 1.0;

  // 生成状态
  int _done = 0;
  int _ok = 0;
  int _fail = 0;
  bool _generating = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // 默认预填：若 memes 至少 2 张，自动配对第 0 张前景 + 第 1 张隐藏
    if (widget.memes.length >= 2) {
      _pairs.add(_Pair(foreground: widget.memes[0], hidden: widget.memes[1]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.watch<LocaleProvider>().l10n;
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('phantom_batch_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.tr('help'),
            onPressed: () => _showHelp(l10n),
          ),
        ],
      ),
      body: _generating || _finished
          ? _buildProgressView(theme, l10n, _pairs.length)
          : _buildEditView(theme, l10n, cs),
      bottomNavigationBar: _buildBottomBar(theme, l10n, cs),
    );
  }

  /// 编辑视图：配对列表 + 添加按钮 + 参数调节
  Widget _buildEditView(ThemeData theme, L10n l10n, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.tr('phantom_batch_desc'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),

        // 配对列表标题
        Row(
          children: [
            Text(l10n.tr('phantom_batch_pairs'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (_pairs.isNotEmpty)
              Text('${_pairs.length}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
          ],
        ),
        const SizedBox(height: 8),

        if (_pairs.isEmpty)
          // 空状态
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(l10n.tr('phantom_batch_pairs_empty'),
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline),
                textAlign: TextAlign.center),
            ),
          )
        else
          // 配对列表
          ...List.generate(_pairs.length, (i) => _buildPairItem(theme, l10n, cs, i)),

        const SizedBox(height: 12),

        // 添加配对按钮区
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add_link),
              label: Text(l10n.tr('phantom_batch_add_pair')),
              onPressed: _addPair,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l10n.tr('phantom_batch_add_foregrounds')),
              onPressed: _addForegroundsBatch,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.tr('phantom_batch_pair_hint'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),

        const SizedBox(height: 16),
        // 参数调节
        _buildParamsPanel(theme, l10n, cs),
      ],
    );
  }

  /// 单个配对项：[前景缩略图] [交换按钮] [隐藏缩略图] [删除按钮]
  Widget _buildPairItem(ThemeData theme, L10n l10n, ColorScheme cs, int index) {
    final pair = _pairs[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            // 前景
            Expanded(child: _buildPairSlot(theme, l10n, cs, pair.foreground, true, index)),
            // 中间交换按钮
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: l10n.tr('phantom_batch_swap'),
              onPressed: () => _swapPair(index),
              visualDensity: VisualDensity.compact,
            ),
            // 隐藏
            Expanded(child: _buildPairSlot(theme, l10n, cs, pair.hidden, false, index)),
            // 删除
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.tr('phantom_batch_remove'),
              onPressed: () => setState(() => _pairs.removeAt(index)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  /// 配对中的一个图片槽：点击可替换
  Widget _buildPairSlot(ThemeData theme, L10n l10n, ColorScheme cs, Meme current, bool isForeground, int pairIndex) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          child: Text(
            isForeground ? l10n.tr('phantom_batch_pair_foreground') : l10n.tr('phantom_batch_pair_hidden'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isForeground ? cs.primary : cs.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _replaceImage(isForeground, pairIndex),
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _buildThumb(theme, current),
                ),
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: cs.surface.withValues(alpha: 0.85),
                    child: Text(current.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 参数调节面板
  Widget _buildParamsPanel(ThemeData theme, L10n l10n, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ChoiceChip(
                label: Text(l10n.tr('phantom_color')),
                selected: _colorMode,
                onSelected: (_) => setState(() => _colorMode = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(l10n.tr('phantom_bw')),
                selected: !_colorMode,
                onSelected: (_) => setState(() => _colorMode = false),
              ),
            ]),
            const SizedBox(height: 12),
            Text('${l10n.tr('phantom_brightness')}: ${_brightnessRatio.toStringAsFixed(2)}'),
            Slider(
              value: _brightnessRatio,
              min: 0.5, max: 2.0, divisions: 30,
              label: _brightnessRatio.toStringAsFixed(2),
              onChanged: (v) => setState(() => _brightnessRatio = v),
            ),
            if (_colorMode) ...[
              Text('${l10n.tr('phantom_color_intensity')}: ${_colorIntensity.toStringAsFixed(2)}'),
              Slider(
                value: _colorIntensity,
                min: 0.0, max: 1.0, divisions: 20,
                label: _colorIntensity.toStringAsFixed(2),
                onChanged: (v) => setState(() => _colorIntensity = v),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 缩略图
  Widget _buildThumb(ThemeData theme, Meme m) {
    final storage = context.read<StorageService>();
    return FutureBuilder<Uint8List?>(
      future: storage.readMemeBytes(m.filePath),
      builder: (_, snap) {
        if (snap.data == null) {
          return Container(
            color: theme.colorScheme.surfaceContainerHigh,
            child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
          );
        }
        return Image.memory(snap.data!, fit: BoxFit.cover);
      },
    );
  }

  /// 进度视图
  Widget _buildProgressView(ThemeData theme, L10n l10n, int total) {
    final cs = theme.colorScheme;
    final progress = total > 0 ? _done / total : 0.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_finished)
              SizedBox(
                width: 80, height: 80,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: cs.primary,
                ),
              )
            else
              Icon(_fail == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 80,
                color: _fail == 0 ? Colors.green : cs.error),
            const SizedBox(height: 24),
            Text(
              _finished
                  ? l10n.tr('phantom_batch_done', args: {
                      'ok': _ok.toString(),
                      'fail': _fail.toString(),
                    })
                  : l10n.tr('phantom_batch_progress', args: {
                      'done': _done.toString(),
                      'total': total.toString(),
                    }),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_finished)
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.tr('close')),
              ),
          ],
        ),
      ),
    );
  }

  /// 底部栏：生成按钮
  Widget _buildBottomBar(ThemeData theme, L10n l10n, ColorScheme cs) {
    final canGen = _pairs.isNotEmpty && !_generating;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: canGen ? () => _startGenerate() : null,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_pairs.isEmpty
              ? l10n.tr('phantom_batch_no_pairs')
              : l10n.tr('phantom_batch_generate_all', args: {'count': _pairs.length.toString()})),
        ),
      ),
    );
  }

  /// 添加一对配对：先选前景，再选隐藏
  Future<void> _addPair() async {
    final l10n = context.read<LocaleProvider>().l10n;
    // 第 1 步：选前景
    final fg = await _pickImageDialog(
      title: l10n.tr('phantom_batch_select_foreground'),
      excludeIds: const <String>{},
    );
    if (fg == null) return;
    // 第 2 步：选隐藏（可复用同一张图）
    final hd = await _pickImageDialog(
      title: l10n.tr('phantom_batch_select_hidden'),
      excludeIds: const <String>{},
    );
    if (hd == null) return;
    setState(() {
      _pairs.add(_Pair(foreground: fg, hidden: hd));
    });
  }

  /// 批量添加前景：用户选多张前景图，剩余图片按顺序作为隐藏图配对
  Future<void> _addForegroundsBatch() async {
    final l10n = context.read<LocaleProvider>().l10n;
    final selected = await _pickMultiImageDialog(
      title: l10n.tr('phantom_batch_add_foregrounds'),
      desc: l10n.tr('phantom_batch_add_foregrounds_desc'),
    );
    if (selected.isEmpty) return;
    // 候选隐藏图池 = 所有 memes - 已选为前景的
    final fgIds = selected.map((e) => e.id).toSet();
    final hiddenPool = widget.memes.where((m) => !fgIds.contains(m.id)).toList();
    if (hiddenPool.isEmpty) {
      // 没有剩余图片，把每张前景自身当作隐藏（自配对）
      setState(() {
        for (final m in selected) {
          _pairs.add(_Pair(foreground: m, hidden: m));
        }
      });
      return;
    }
    setState(() {
      for (var i = 0; i < selected.length; i++) {
        final hidden = hiddenPool[i % hiddenPool.length];
        _pairs.add(_Pair(foreground: selected[i], hidden: hidden));
      }
    });
  }

  /// 替换配对中的某张图
  Future<void> _replaceImage(bool isForeground, int pairIndex) async {
    final l10n = context.read<LocaleProvider>().l10n;
    final picked = await _pickImageDialog(
      title: isForeground
          ? l10n.tr('phantom_batch_select_foreground')
          : l10n.tr('phantom_batch_select_hidden'),
      excludeIds: const <String>{},
    );
    if (picked == null) return;
    setState(() {
      if (isForeground) {
        _pairs[pairIndex].foreground = picked;
      } else {
        _pairs[pairIndex].hidden = picked;
      }
    });
  }

  /// 交换配对中的前景与隐藏
  void _swapPair(int index) {
    setState(() {
      final p = _pairs[index];
      final tmp = p.foreground;
      p.foreground = p.hidden;
      p.hidden = tmp;
    });
  }

  /// 单图选择对话框：从 widget.memes 中选一张
  Future<Meme?> _pickImageDialog({
    required String title,
    required Set<String> excludeIds,
  }) async {
    final theme = Theme.of(context);
    final candidates = widget.memes.where((m) => !excludeIds.contains(m.id)).toList();
    if (candidates.isEmpty) return null;
    return showDialog<Meme>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 100,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (c, i) {
              final m = candidates[i];
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, m),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: _buildThumb(theme, m),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.read<LocaleProvider>().l10n.tr('cancel')),
          ),
        ],
      ),
    );
  }

  /// 多图选择对话框：返回选中的多张图
  Future<List<Meme>> _pickMultiImageDialog({
    required String title,
    String? desc,
  }) async {
    final theme = Theme.of(context);
    final l10n = context.read<LocaleProvider>().l10n;
    final selected = <String>{};
    final result = await showDialog<List<Meme>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (desc != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  ),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    itemCount: widget.memes.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 100,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (c, i) {
                      final m = widget.memes[i];
                      final isSel = selected.contains(m.id);
                      return GestureDetector(
                        onTap: () {
                          setSt(() {
                            if (isSel) {
                              selected.remove(m.id);
                            } else {
                              selected.add(m.id);
                            }
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSel ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                              width: isSel ? 3 : 1,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: _buildThumb(theme, m),
                              ),
                              if (isSel)
                                Positioned(
                                  top: 2, right: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.check, size: 12, color: theme.colorScheme.onPrimary),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.tr('cancel')),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      final picked = widget.memes.where((m) => selected.contains(m.id)).toList();
                      Navigator.pop(ctx, picked);
                    },
              child: Text(l10n.tr('confirm')),
            ),
          ],
        ),
      ),
    );
    return result ?? [];
  }

  /// 启动批量生成
  Future<void> _startGenerate() async {
    if (_pairs.isEmpty) return;
    final prov = context.read<MemeProvider>();
    final tool = context.read<ImageToolService>();
    final l10n = context.read<LocaleProvider>().l10n;
    final messenger = ScaffoldMessenger.of(context);

    // 拍快照，避免生成过程中列表变化
    final pairsSnapshot = List<_Pair>.from(_pairs);
    final total = pairsSnapshot.length;

    setState(() {
      _generating = true;
      _finished = false;
      _done = 0;
      _ok = 0;
      _fail = 0;
    });

    for (var i = 0; i < total; i++) {
      final p = pairsSnapshot[i];
      try {
        await tool.makePhantomTank(
          p.foreground.filePath,
          p.hidden.filePath,
          colorMode: _colorMode,
          brightnessRatio: _brightnessRatio,
          colorIntensity: _colorIntensity,
          name: '${p.foreground.name}_${p.hidden.name}_phantom',
        );
        _ok++;
      } catch (_) {
        _fail++;
      }
      _done = i + 1;
      if (mounted) setState(() {});
    }

    await prov.loadAll();
    if (mounted) {
      setState(() {
        _generating = false;
        _finished = true;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.tr('phantom_batch_done',
            args: {'ok': _ok.toString(), 'fail': _fail.toString()})),
      ));
    }
  }

  void _showHelp(L10n l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('phantom_batch_title')),
        content: Text(l10n.tr('phantom_batch_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('close'))),
        ],
      ),
    );
  }
}
