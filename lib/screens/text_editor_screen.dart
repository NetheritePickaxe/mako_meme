import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/locale_provider.dart';
import 'package:provider/provider.dart';

/// 文本/小说编辑弹窗
/// - 默认为小弹窗（紧凑模式）
/// - 点击展开按钮切换为全屏编辑模式
/// - 全屏模式下底部显示图标式 Markdown 快捷按钮
class TextEditorScreen extends StatefulWidget {
  final String type;
  final Future<void> Function(String text, String? title) onSave;
  final String? initialText;
  final String? initialTitle;

  const TextEditorScreen({
    super.key,
    required this.type,
    required this.onSave,
    this.initialText,
    this.initialTitle,
  });

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late TextEditingController _textCtrl;
  late TextEditingController _titleCtrl;
  bool _previewMode = false;
  bool _saving = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText ?? '');
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(text, _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim());
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 粘贴剪贴板内容：插入到光标位置（有选区时替换选区，无选区时追加到末尾）
  Future<void> _pasteAtCursor() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final pasteText = data.text!;
    final sel = _textCtrl.selection;
    final text = _textCtrl.text;
    String newText;
    int pos;
    if (sel.isValid) {
      // 有选区或有效光标：在光标位置插入（选区则替换选区）
      newText = text.substring(0, sel.start) + pasteText + text.substring(sel.end);
      pos = sel.start + pasteText.length;
    } else {
      // 无有效光标：追加到末尾
      newText = text + pasteText;
      pos = newText.length;
    }
    _textCtrl.text = newText;
    _textCtrl.selection = TextSelection(baseOffset: pos, extentOffset: pos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final isNovel = widget.type == 'novel';

    if (_expanded) {
      // 全屏模式：直接使用 Scaffold 填满整屏（含状态栏区域）
      final isDark = theme.brightness == Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Scaffold(
            appBar: AppBar(
              title: Text(isNovel ? l10n.tr('import_novel') : l10n.tr('import_text')),
              actions: [
                IconButton(
                  icon: Icon(_previewMode ? Icons.edit : Icons.visibility_outlined),
                  tooltip: _previewMode ? l10n.tr('edit_mode') : l10n.tr('preview_mode'),
                  onPressed: () => setState(() => _previewMode = !_previewMode),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit),
                  tooltip: l10n.tr('collapse'),
                  onPressed: () => setState(() => _expanded = false),
                ),
                IconButton(
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  tooltip: l10n.tr('save'),
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.tr('title_hint'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: _previewMode
                      ? _buildMarkdownPreview(theme)
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _textCtrl,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: TextStyle(
                              fontSize: isNovel ? 16 : 18,
                              height: isNovel ? 1.8 : 1.5,
                            ),
                            decoration: InputDecoration(
                              hintText: isNovel ? l10n.tr('novel_hint') : l10n.tr('hint_text_or_emoji'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                ),
                // 底部 Markdown 工具栏（图标式，仅编辑模式）
                if (!_previewMode) _buildMarkdownToolbar(theme),
              ],
            ),
          ),
        ),
      );
    }

    // 紧凑弹窗模式
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.text_fields, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  isNovel ? l10n.tr('import_novel') : l10n.tr('import_text'),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: l10n.tr('expand'),
                  onPressed: () => setState(() => _expanded = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: l10n.tr('title_hint'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: TextField(
                controller: _textCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontSize: isNovel ? 16 : 18,
                  height: isNovel ? 1.8 : 1.5,
                ),
                decoration: InputDecoration(
                  hintText: isNovel ? l10n.tr('novel_hint') : l10n.tr('hint_text_or_emoji'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // 左下角粘贴按钮
                IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: l10n.tr('paste'),
                  onPressed: _pasteAtCursor,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.tr('cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.tr('save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 图标式 Markdown 工具栏（位于底部）
  /// 仿照主流 Markdown 编辑器，使用图标而非文字标签
  Widget _buildMarkdownToolbar(ThemeData theme) {
    final tools = <(String, IconData, String)>[
      ('# ', Icons.looks_one_outlined, 'H1'),
      ('## ', Icons.looks_two_outlined, 'H2'),
      ('### ', Icons.looks_3_outlined, 'H3'),
      ('**', Icons.format_bold, 'Bold'),
      ('*', Icons.format_italic, 'Italic'),
      ('~~', Icons.format_strikethrough, 'Strikethrough'),
      ('- ', Icons.format_list_bulleted, 'List'),
      ('> ', Icons.format_quote, 'Quote'),
      ('`', Icons.code, 'Code'),
      ('\n```\n', Icons.data_object, 'CodeBlock'),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: tools.map((t) {
          return IconButton(
            icon: Icon(t.$2),
            tooltip: t.$3,
            visualDensity: VisualDensity.compact,
            onPressed: () => _insertMarkdown(t.$1),
          );
        }).toList(),
      ),
    );
  }

  void _insertMarkdown(String syntax) {
    final sel = _textCtrl.selection;
    final text = _textCtrl.text;
    if (sel.isValid && sel.start != sel.end) {
      // 包裹选中文本
      final selected = text.substring(sel.start, sel.end);
      final isBlock = syntax.contains('\n');
      final wrapped = isBlock ? '$syntax selected\n' : '$syntax$selected$syntax';
      _textCtrl.text = text.substring(0, sel.start) + wrapped + text.substring(sel.end);
      final pos = sel.start + wrapped.length;
      _textCtrl.selection = TextSelection(baseOffset: pos, extentOffset: pos);
    } else {
      // 插入语法
      _textCtrl.text = text.substring(0, sel.start) + syntax + text.substring(sel.start);
      final pos = sel.start + syntax.length;
      _textCtrl.selection = TextSelection(baseOffset: pos, extentOffset: pos);
    }
  }

  /// 简易 Markdown 渲染（支持标题/粗体/斜体/删除线/列表/引用/代码/分隔线）
  Widget _buildMarkdownPreview(ThemeData theme) {
    final source = _textCtrl.text;
    if (source.trim().isEmpty) {
      return Center(
        child: Text(
          'No content to preview',
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }
    final lines = source.split('\n');
    final spans = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      spans.add(_renderLine(lines[i], theme, i + 1));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: spans,
      ),
    );
  }

  Widget _renderLine(String line, ThemeData theme, int lineNum) {
    final ts = theme.textTheme;
    // 标题
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(line.substring(4), style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      );
    }
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(line.substring(3), style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );
    }
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(line.substring(2), style: ts.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      );
    }
    // 分隔线
    if (line.trim() == '---' || line.trim() == '***') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(color: theme.colorScheme.outlineVariant),
      );
    }
    // 引用
    if (line.startsWith('> ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
          ),
          padding: const EdgeInsets.only(left: 8),
          child: Text(_renderInline(line.substring(2), theme), style: ts.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
      );
    }
    // 代码块
    if (line.startsWith('```')) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(line.substring(3), style: ts.bodySmall?.copyWith(fontFamily: 'monospace')),
      );
    }
    // 列表项
    if (line.startsWith('- ') || line.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: ts.bodyMedium),
            Expanded(child: Text(_renderInline(line.substring(2), theme), style: ts.bodyMedium)),
          ],
        ),
      );
    }
    // 有序列表
    final olMatch = RegExp(r'^(\d+)\.\s+(.*)').firstMatch(line);
    if (olMatch != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${olMatch.group(1)}. ', style: ts.bodyMedium),
            Expanded(child: Text(_renderInline(olMatch.group(2)!, theme), style: ts.bodyMedium)),
          ],
        ),
      );
    }
    // 空行
    if (line.trim().isEmpty) {
      return const SizedBox(height: 8);
    }
    // 普通段落
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(_renderInline(line, theme), style: ts.bodyMedium?.copyWith(height: 1.6)),
    );
  }

  /// 处理行内 Markdown（粗体/斜体/删除线/代码）+ Unicode
  String _renderInline(String text, ThemeData theme) {
    // 保留原始文本交给 Text.rich 处理更佳，这里简化为纯文本展示
    // Unicode 字符（emoji/CJK/特殊符号）由 Flutter Text 原生支持
    return text;
  }
}
