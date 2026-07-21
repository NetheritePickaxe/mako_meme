import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/locale_provider.dart';
import 'package:provider/provider.dart';

/// 文本编辑弹窗：简单 AlertDialog，标题 + 输入框 + 粘贴/取消/保存
/// 仅纯文本编辑，标题用首行/前 30 字符自动生成
class TextEditorDialog {
  /// 显示文本编辑弹窗
  static Future<void> show(
    BuildContext context, {
    required String type,
    required Future<void> Function(String text, String? title) onSave,
    String? initialText,
    String? initialTitle,
  }) {
    return showDialog(
      context: context,
      builder: (_) => _TextEditorDialog(
        type: type,
        onSave: onSave,
        initialText: initialText,
        initialTitle: initialTitle,
      ),
    );
  }
}

class _TextEditorDialog extends StatefulWidget {
  final String type;
  final Future<void> Function(String text, String? title) onSave;
  final String? initialText;
  final String? initialTitle;

  const _TextEditorDialog({
    required this.type,
    required this.onSave,
    this.initialText,
    this.initialTitle,
  });

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late TextEditingController _textCtrl;
  bool _saving = false;

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
      await widget.onSave(text, null);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 粘贴剪贴板内容到光标位置
  Future<void> _pasteAtCursor() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final pasteText = data.text!;
    final sel = _textCtrl.selection;
    final text = _textCtrl.text;
    String newText;
    int pos;
    if (sel.isValid) {
      newText = text.substring(0, sel.start) + pasteText + text.substring(sel.end);
      pos = sel.start + pasteText.length;
    } else {
      newText = text + pasteText;
      pos = newText.length;
    }
    _textCtrl.text = newText;
    _textCtrl.selection = TextSelection(baseOffset: pos, extentOffset: pos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<LocaleProvider>().l10n;
    final isNovel = widget.type == 'novel';

    return AlertDialog(
      title: Text(isNovel ? l10n.tr('import_novel') : l10n.tr('import_text')),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _textCtrl,
          maxLines: 10,
          minLines: 6,
          autofocus: true,
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
      actions: [
        TextButton.icon(
          onPressed: _pasteAtCursor,
          icon: const Icon(Icons.content_paste),
          label: Text(l10n.tr('paste')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.tr('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.tr('save')),
        ),
      ],
    );
  }
}
