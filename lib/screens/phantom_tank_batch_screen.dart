import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/image_tool_service.dart';
import '../services/storage_service.dart';
import '../l10n/l10n.dart';

/// 批量幻影坦克生成界面
///
/// 用于从 3+ 张图片批量生成幻影坦克：
/// - 用户选择一张前景图（默认第一张）
/// - 其余 N-1 张作为隐藏图，逐张与前景合成
/// - 共生成 N-1 张幻影坦克，保存为新 meme
///
/// 合成参数（彩色/黑白、亮度比例、色彩强度）对所有生成共享。
class PhantomTankBatchScreen extends StatefulWidget {
  final List<Meme> memes;
  const PhantomTankBatchScreen({super.key, required this.memes});

  @override
  State<PhantomTankBatchScreen> createState() => _PhantomTankBatchScreenState();
}

class _PhantomTankBatchScreenState extends State<PhantomTankBatchScreen> {
  int _foregroundIndex = 0;
  bool _colorMode = true;
  double _brightnessRatio = 1.0;
  double _colorIntensity = 1.0;

  // 生成状态：null=未开始，否则为进度
  int _done = 0;
  int _ok = 0;
  int _fail = 0;
  bool _generating = false;
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.watch<LocaleProvider>().l10n;
    final cs = theme.colorScheme;

    // 隐藏图列表 = 除前景外的所有图片
    final hiddenList = <Meme>[];
    for (var i = 0; i < widget.memes.length; i++) {
      if (i != _foregroundIndex) hiddenList.add(widget.memes[i]);
    }

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
          ? _buildProgressView(theme, l10n, hiddenList.length)
          : _buildEditView(theme, l10n, cs, hiddenList),
      bottomNavigationBar: _buildBottomBar(theme, l10n, cs, hiddenList.length),
    );
  }

  /// 编辑视图：前景预览 + 隐藏图网格 + 参数调节
  Widget _buildEditView(ThemeData theme, L10n l10n, ColorScheme cs, List<Meme> hiddenList) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.tr('phantom_batch_desc'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),

        // 前景图预览
        Text(l10n.tr('phantom_batch_foreground'),
          style: theme.textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildForegroundSelector(theme, l10n, cs),
        const SizedBox(height: 16),

        // 隐藏图网格
        Text(l10n.tr('phantom_batch_hidden', args: {'count': hiddenList.length.toString()}),
          style: theme.textTheme.titleSmall?.copyWith(color: cs.outline, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: hiddenList.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 100,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemBuilder: (ctx, i) => _buildThumb(theme, hiddenList[i]),
        ),
        const SizedBox(height: 16),

        // 参数调节
        _buildParamsPanel(theme, l10n, cs),
      ],
    );
  }

  /// 前景图选择器：横向滚动所有图片，当前选中的高亮
  Widget _buildForegroundSelector(ThemeData theme, L10n l10n, ColorScheme cs) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.memes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final m = widget.memes[i];
          final selected = i == _foregroundIndex;
          return GestureDetector(
            onTap: () => setState(() => _foregroundIndex = i),
            child: Container(
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _buildThumb(theme, m),
                  ),
                  if (selected)
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check, size: 12, color: cs.onPrimary),
                      ),
                    ),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.8),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: Text(m.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
            // 彩色/黑白
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
            // 亮度
            Text('${l10n.tr('phantom_brightness')}: ${_brightnessRatio.toStringAsFixed(2)}'),
            Slider(
              value: _brightnessRatio,
              min: 0.5, max: 2.0, divisions: 30,
              label: _brightnessRatio.toStringAsFixed(2),
              onChanged: (v) => setState(() => _brightnessRatio = v),
            ),
            // 色彩强度
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
  Widget _buildBottomBar(ThemeData theme, L10n l10n, ColorScheme cs, int hiddenCount) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _generating ? null : () => _startGenerate(),
          icon: const Icon(Icons.auto_awesome),
          label: Text(l10n.tr('phantom_batch_generate_all',
              args: {'count': hiddenCount.toString()})),
        ),
      ),
    );
  }

  /// 启动批量生成
  Future<void> _startGenerate() async {
    final prov = context.read<MemeProvider>();
    final tool = context.read<ImageToolService>();
    final l10n = context.read<LocaleProvider>().l10n;
    final messenger = ScaffoldMessenger.of(context);

    final fg = widget.memes[_foregroundIndex];
    final hiddenList = <Meme>[];
    for (var i = 0; i < widget.memes.length; i++) {
      if (i != _foregroundIndex) hiddenList.add(widget.memes[i]);
    }
    final total = hiddenList.length;

    setState(() {
      _generating = true;
      _finished = false;
      _done = 0;
      _ok = 0;
      _fail = 0;
    });

    for (var i = 0; i < total; i++) {
      try {
        await tool.makePhantomTank(
          fg.filePath, hiddenList[i].filePath,
          colorMode: _colorMode,
          brightnessRatio: _brightnessRatio,
          colorIntensity: _colorIntensity,
          name: '${fg.name}_${hiddenList[i].name}_phantom',
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
