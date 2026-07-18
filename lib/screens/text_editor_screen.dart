import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/locale_provider.dart';
import 'package:provider/provider.dart';

/// 文本/小说编辑弹窗
/// - 默认为小弹窗（紧凑模式）
/// - 点击展开按钮切换为全屏编辑模式
/// - 仅纯文本编辑，不再要求标题（标题用首行/前 30 字符自动生成）
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
  bool _saving = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      // 不再强制要求标题；标题由存储层用前 30 字符自动生成
      await widget.onSave(text, null);
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
            body: Padding(
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
}
