import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import '../providers/locale_provider.dart';
import '../providers/meme_provider.dart';
import '../services/image_tool_service.dart';
import '../services/storage_service.dart';
import '../models/meme.dart';
import 'keyboard_setup_screen.dart';

/// 工具页：图片格式转换、尺寸修改、多图转 GIF/APNG、表情包输入法
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocaleProvider>().l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('tools')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.swap_horiz), text: l10n.tr('tool_convert')),
            Tab(icon: const Icon(Icons.aspect_ratio), text: l10n.tr('tool_resize')),
            Tab(icon: const Icon(Icons.animation), text: l10n.tr('tool_to_gif')),
            Tab(icon: const Icon(Icons.keyboard_outlined), text: l10n.tr('keyboard_setup')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ConvertTab(),
          _ResizeTab(),
          _AnimationTab(),
          _ImeTab(),
        ],
      ),
    );
  }
}

// ===================== 表情包输入法 =====================

class _ImeTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (!isAndroid) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.desktop_access_disabled, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text(l10n.tr('keyboard_feature_unavailable'),
                  style: TextStyle(color: cs.outline), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.keyboard_outlined, size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(l10n.tr('keyboard_setup'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(l10n.tr('keyboard_setup_desc'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const KeyboardSetupScreen())),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.tr('open')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== 格式转换 =====================

class _ConvertTab extends StatefulWidget {
  @override
  State<_ConvertTab> createState() => _ConvertTabState();
}

class _ConvertTabState extends State<_ConvertTab> {
  String _selectedFormat = 'png';
  int _quality = 90;
  Meme? _selectedMeme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final prov = context.watch<MemeProvider>();
    // 仅显示可转换的图片类型（排除 SVG/PSD/PDF/小说/文字）
    final candidates = prov.memes.where((m) =>
        m.isImageType && !m.isVector && !m.isPsd && !m.isPdf).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 源图选择
          Text(l10n.tr('source_image'),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _MemePicker(
            candidates: candidates,
            selected: _selectedMeme,
            onSelected: (m) => setState(() => _selectedMeme = m),
          ),
          const SizedBox(height: 20),
          // 输出格式
          Text(l10n.tr('output_format'),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ImageToolService.outputFormats.map((f) {
              return ChoiceChip(
                label: Text(f.toUpperCase()),
                selected: _selectedFormat == f,
                onSelected: (_) => setState(() => _selectedFormat = f),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 质量（仅 JPG/WebP 有意义）
          if (_selectedFormat == 'jpg' || _selectedFormat == 'webp') ...[
            Text('${l10n.tr('quality')}: $_quality',
              style: theme.textTheme.bodyMedium),
            Slider(
              value: _quality.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              onChanged: (v) => setState(() => _quality = v.round()),
            ),
            const SizedBox(height: 16),
          ],
          // 执行按钮
          FilledButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: Text(l10n.tr('convert')),
            onPressed: _selectedMeme == null ? null : _doConvert,
          ),
        ],
      ),
    );
  }

  Future<void> _doConvert() async {
    if (_selectedMeme == null) return;
    final l10n = context.read<LocaleProvider>().l10n;
    final tool = context.read<ImageToolService>();
    final prov = context.read<MemeProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      _showLoading(l10n.tr('converting'));
      await tool.convertFormat(
        _selectedMeme!.filePath,
        _selectedFormat,
        quality: _quality,
        name: _selectedMeme!.name,
      );
      await prov.loadAll();
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text(l10n.tr('convert_success'))));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text('${l10n.tr('convert_failed')}: $e')));
      }
    }
  }

  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 16),
            Text(msg),
          ],
        ),
      ),
    );
  }
}

// ===================== 尺寸修改 =====================

class _ResizeTab extends StatefulWidget {
  @override
  State<_ResizeTab> createState() => _ResizeTabState();
}

class _ResizeTabState extends State<_ResizeTab> {
  Meme? _selectedMeme;
  // 模式：'percent' 或 'pixel'
  String _mode = 'percent';
  int _percent = 50;
  int _targetWidth = 0;
  int _targetHeight = 0;
  bool _keepRatio = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final prov = context.watch<MemeProvider>();
    final candidates = prov.memes.where((m) =>
        m.isImageType && !m.isVector && !m.isPsd && !m.isPdf).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tr('source_image'),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _MemePicker(
            candidates: candidates,
            selected: _selectedMeme,
            onSelected: (m) => setState(() => _selectedMeme = m),
          ),
          const SizedBox(height: 20),
          // 模式切换
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'percent', label: Text(l10n.tr('by_percent'))),
              ButtonSegment(value: 'pixel', label: Text(l10n.tr('by_pixel'))),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 'percent') ...[
            Text('${l10n.tr('scale')}: $_percent%',
              style: theme.textTheme.bodyMedium),
            Slider(
              value: _percent.toDouble(),
              min: 10,
              max: 200,
              divisions: 19,
              label: '$_percent%',
              onChanged: (v) => setState(() => _percent = v.round()),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.tr('width'),
                      suffixText: 'px',
                    ),
                    onChanged: (v) => _targetWidth = int.tryParse(v) ?? 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.tr('height'),
                      suffixText: 'px',
                    ),
                    onChanged: (v) => _targetHeight = int.tryParse(v) ?? 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(l10n.tr('keep_ratio')),
              value: _keepRatio,
              onChanged: (v) => setState(() => _keepRatio = v),
              dense: true,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.aspect_ratio),
            label: Text(l10n.tr('resize')),
            onPressed: _selectedMeme == null ? null : _doResize,
          ),
        ],
      ),
    );
  }

  Future<void> _doResize() async {
    if (_selectedMeme == null) return;
    final l10n = context.read<LocaleProvider>().l10n;
    final tool = context.read<ImageToolService>();
    final prov = context.read<MemeProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      _showLoading(l10n.tr('resizing'));
      if (_mode == 'percent') {
        await tool.resize(
          _selectedMeme!.filePath,
          percent: _percent / 100.0,
          name: _selectedMeme!.name,
        );
      } else {
        await tool.resize(
          _selectedMeme!.filePath,
          width: _targetWidth > 0 ? _targetWidth : null,
          height: _targetHeight > 0 ? _targetHeight : null,
          name: _selectedMeme!.name,
        );
      }
      await prov.loadAll();
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text(l10n.tr('resize_success'))));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text('${l10n.tr('resize_failed')}: $e')));
      }
    }
  }

  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 16),
            Text(msg),
          ],
        ),
      ),
    );
  }
}

// ===================== 多图转 GIF/APNG =====================

class _AnimationTab extends StatefulWidget {
  @override
  State<_AnimationTab> createState() => _AnimationTabState();
}

class _AnimationTabState extends State<_AnimationTab> {
  final List<Meme> _selected = [];
  int _frameDuration = 200;
  // 'gif' 或 'apng'
  String _format = 'gif';

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final prov = context.watch<MemeProvider>();
    final candidates = prov.memes.where((m) =>
        m.isImageType && !m.isVector && !m.isPsd && !m.isPdf && !m.isAnimated).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选择多张图片
          Row(
            children: [
              Text(l10n.tr('select_frames'),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_selected.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 18),
                  label: Text(l10n.tr('clear')),
                  onPressed: () => setState(() => _selected.clear()),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${l10n.tr('selected_count')}: ${_selected.length}',
            style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          // 候选网格
          SizedBox(
            height: 200,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: candidates.length,
              itemBuilder: (ctx, i) {
                final m = candidates[i];
                final idx = _selected.indexWhere((s) => s.id == m.id);
                final isSelected = idx >= 0;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selected.removeAt(idx);
                      } else {
                        _selected.add(m);
                      }
                    });
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(child: _MemeThumb(meme: m)),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected ? theme.colorScheme.primary : Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected ? Icons.check : Icons.add,
                            size: 14,
                            color: isSelected ? theme.colorScheme.onPrimary : Colors.white,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${idx + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          // 已选顺序列表
          if (_selected.isNotEmpty) ...[
            Text(l10n.tr('frame_order'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: List.generate(_selected.length, (i) {
                return Chip(
                  label: Text('${i + 1}. ${_selected[i].name}',
                    style: const TextStyle(fontSize: 11)),
                  onDeleted: () => setState(() => _selected.removeAt(i)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }),
            ),
            const SizedBox(height: 16),
          ],
          // 帧时长
          Text('${l10n.tr('frame_duration')}: ${_frameDuration}ms',
            style: theme.textTheme.bodyMedium),
          Slider(
            value: _frameDuration.toDouble(),
            min: 50,
            max: 1000,
            divisions: 19,
            label: '${_frameDuration}ms',
            onChanged: (v) => setState(() => _frameDuration = v.round()),
          ),
          const SizedBox(height: 8),
          // 格式选择
          Row(
            children: [
              ChoiceChip(
                label: const Text('GIF'),
                selected: _format == 'gif',
                onSelected: (_) => setState(() => _format = 'gif'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('APNG'),
                selected: _format == 'apng',
                onSelected: (_) => setState(() => _format = 'apng'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 执行按钮
          FilledButton.icon(
            icon: Icon(_format == 'gif' ? Icons.gif : Icons.animation),
            label: Text(l10n.tr(_format == 'gif' ? 'make_gif' : 'make_apng')),
            onPressed: _selected.length < 2 ? null : _doConvert,
          ),
        ],
      ),
    );
  }

  Future<void> _doConvert() async {
    if (_selected.length < 2) return;
    final l10n = context.read<LocaleProvider>().l10n;
    final tool = context.read<ImageToolService>();
    final prov = context.read<MemeProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      _showLoading(l10n.tr('converting'));
      final paths = _selected.map((m) => m.filePath).toList();
      if (_format == 'gif') {
        await tool.imagesToGif(paths, frameDurationMs: _frameDuration);
      } else {
        await tool.imagesToApng(paths, frameDurationMs: _frameDuration);
      }
      await prov.loadAll();
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text(l10n.tr('convert_success'))));
        setState(() => _selected.clear());
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text('${l10n.tr('convert_failed')}: $e')));
      }
    }
  }

  void _showLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 16),
            Text(msg),
          ],
        ),
      ),
    );
  }
}

// ===================== 通用组件 =====================

/// 图片选择器：水平网格列出可选图片
class _MemePicker extends StatelessWidget {
  final List<Meme> candidates;
  final Meme? selected;
  final ValueChanged<Meme> onSelected;

  const _MemePicker({
    required this.candidates,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (candidates.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text('No images', style: TextStyle(color: theme.colorScheme.outline)),
      );
    }
    return SizedBox(
      height: 120,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 1,
          childAspectRatio: 1,
          mainAxisSpacing: 6,
        ),
        itemCount: candidates.length,
        itemBuilder: (ctx, i) {
          final m = candidates[i];
          final isSelected = selected?.id == m.id;
          return GestureDetector(
            onTap: () => onSelected(m),
            child: Stack(
              children: [
                Positioned.fill(child: _MemeThumb(meme: m)),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.primary, width: 3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 缩略图
class _MemeThumb extends StatefulWidget {
  final Meme meme;
  const _MemeThumb({required this.meme});

  @override
  State<_MemeThumb> createState() => _MemeThumbState();
}

class _MemeThumbState extends State<_MemeThumb> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final storage = context.read<StorageService>();
    final b = await storage.readMemeBytes(widget.meme.displayPath);
    if (mounted) setState(() { _bytes = b; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : const Center(child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    );
  }
}
