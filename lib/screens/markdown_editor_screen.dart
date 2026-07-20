import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';

/// Markdown 编辑模式
enum _MdMode { edit, preview, split }

/// Markdown 编辑器界面
///
/// 用于"作为 Markdown 导入"：直接进入全屏 Markdown 编辑器
/// - 编辑模式：纯文本编辑
/// - 预览模式：渲染后的 Markdown
/// - 分屏模式：左编辑右预览
/// 标题用首个 # 标题或前 30 字符自动生成
class MarkdownEditorScreen extends StatefulWidget {
  final Future<void> Function(String text, String? title) onSave;
  final String? initialText;
  final String? initialTitle;

  const MarkdownEditorScreen({
    super.key,
    required this.onSave,
    this.initialText,
    this.initialTitle,
  });

  @override
  State<MarkdownEditorScreen> createState() => _MarkdownEditorScreenState();
}

class _MarkdownEditorScreenState extends State<MarkdownEditorScreen> {
  late TextEditingController _ctrl;
  _MdMode _mode = _MdMode.edit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText ?? '');
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 从文本中提取标题：首个 # 标题，否则前 30 字符
  String _extractTitle(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }
    }
    final firstNonEmpty = lines.firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    if (firstNonEmpty.isEmpty) return 'Markdown';
    return firstNonEmpty.length > 30
        ? '${firstNonEmpty.substring(0, 30)}...'
        : firstNonEmpty;
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(text, _extractTitle(text));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 在光标位置插入 Markdown 语法包裹
  void _insertWrap(String prefix, {String? suffix}) {
    final s = suffix ?? prefix;
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    if (!sel.isValid || sel.start == sel.end) {
      // 无选区：仅插入前缀，光标置于中间
      final pos = sel.baseOffset;
      final newText = text.substring(0, pos) + prefix + s + text.substring(pos);
      _ctrl.text = newText;
      _ctrl.selection = TextSelection.collapsed(offset: pos + prefix.length);
      return;
    }
    // 有选区：包裹选中文本
    final selected = text.substring(sel.start, sel.end);
    final newText = text.substring(0, sel.start) + prefix + selected + s + text.substring(sel.end);
    _ctrl.text = newText;
    _ctrl.selection = TextSelection(
      baseOffset: sel.start + prefix.length,
      extentOffset: sel.end + prefix.length,
    );
  }

  /// 在光标行首插入（如 # 标题、- 列表项）
  void _insertLinePrefix(String prefix) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    if (!sel.isValid) return;
    // 找到光标所在行的起始位置
    int lineStart = sel.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    final newText = text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _ctrl.text = newText;
    _ctrl.selection = TextSelection.collapsed(offset: sel.start + prefix.length);
  }

  Widget _buildEditor(BuildContext context, ThemeData theme) {
    final l10n = context.read<LocaleProvider>().l10n;
    return TextField(
      controller: _ctrl,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
        fontSize: 15,
        height: 1.6,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        hintText: l10n.tr('md_hint'),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    return MarkdownBody(
      data: _ctrl.text.isEmpty ? '## Preview\n\n*Nothing yet.*' : _ctrl.text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: TextStyle(color: cs.onSurface),
        h1: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
        h2: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
        h3: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
        code: TextStyle(
          backgroundColor: cs.surfaceContainerHighest,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: cs.primary, width: 3)),
        ),
      ),
    );
  }

  /// 工具栏：常用 Markdown 语法快捷按钮
  Widget _buildToolbar(ThemeData theme, LocaleProvider lp) {
    final l10n = lp.l10n;
    // 包裹型：选中文本后包裹前后缀
    final wrapItems = <(IconData, String, String?, String)>[
      (Icons.format_bold, '**', null, l10n.tr('md_bold')),
      (Icons.format_italic, '*', null, l10n.tr('md_italic')),
      (Icons.format_strikethrough, '~~', null, l10n.tr('md_strike')),
      (Icons.code, '`', null, l10n.tr('md_inline_code')),
      (Icons.link, '[', ']()', l10n.tr('md_link')),
      (Icons.format_quote, '> ', null, l10n.tr('md_quote')),
    ];
    // 行首型：在光标行首插入前缀
    final lineItems = <(IconData, String, String)>[
      (Icons.title, '# ', l10n.tr('md_heading')),
      (Icons.format_list_bulleted, '- ', l10n.tr('md_bullet_list')),
      (Icons.format_list_numbered, '1. ', l10n.tr('md_numbered_list')),
      (Icons.horizontal_rule, '---\n', l10n.tr('md_hr')),
    ];
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final it in wrapItems)
              IconButton(
                icon: Icon(it.$1, size: 18),
                tooltip: it.$4,
                onPressed: () => _insertWrap(it.$2, suffix: it.$3),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            Container(
              width: 1, height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: theme.dividerColor,
            ),
            for (final it in lineItems)
              IconButton(
                icon: Icon(it.$1, size: 18),
                tooltip: it.$3,
                onPressed: () => _insertLinePrefix(it.$2),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lp = context.watch<LocaleProvider>();
    final l10n = lp.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('md_editor_title')),
        actions: [
          // 模式切换：编辑 / 分屏 / 预览
          SegmentedButton<_MdMode>(
            segments: [
              ButtonSegment(
                value: _MdMode.edit,
                icon: const Icon(Icons.edit, size: 16),
                tooltip: l10n.tr('md_mode_edit'),
              ),
              ButtonSegment(
                value: _MdMode.split,
                icon: const Icon(Icons.view_column, size: 16),
                tooltip: l10n.tr('md_mode_split'),
              ),
              ButtonSegment(
                value: _MdMode.preview,
                icon: const Icon(Icons.visibility, size: 16),
                tooltip: l10n.tr('md_mode_preview'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(l10n.tr('save')),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: () {
              switch (_mode) {
                case _MdMode.edit:
                  return _buildEditor(context, theme);
                case _MdMode.preview:
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildPreview(context, theme),
                  );
                case _MdMode.split:
                  return Row(
                    children: [
                      Expanded(child: _buildEditor(context, theme)),
                      VerticalDivider(width: 1, color: theme.dividerColor),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _buildPreview(context, theme),
                        ),
                      ),
                    ],
                  );
              }
            }(),
          ),
          // 工具栏仅在编辑/分屏模式显示
          if (_mode != _MdMode.preview) _buildToolbar(theme, lp),
        ],
      ),
    );
  }
}
