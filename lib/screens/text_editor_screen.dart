import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/locale_provider.dart';
import 'package:provider/provider.dart';

/// 文本编辑弹窗
///
/// 紧凑模式：Dialog 形式（居中卡片，输入框固定高度）
/// 全屏模式：Navigator.push 独立全屏路由（覆盖状态栏），与 Dialog 共享 controller
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
  // 全屏路由保存成功标志：用于 _enterFullscreen 返回后判断是否关闭 Dialog
  bool _savedFromFullscreen = false;

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

  /// 实际保存逻辑（不 pop），返回是否保存成功
  Future<bool> _doSave() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return false;
    setState(() => _saving = true);
    try {
      await widget.onSave(text, null);
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (await _doSave()) {
      if (mounted) Navigator.pop(context);
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

  /// 进入全屏编辑：push 独立全屏路由，与 Dialog 共享 controller
  /// 全屏保存成功后 pop 全屏，返回时检测标志再 pop Dialog
  Future<void> _enterFullscreen() async {
    final l10n = context.read<LocaleProvider>().l10n;
    _savedFromFullscreen = false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TextEditorFullscreen(
          controller: _textCtrl,
          title: widget.type == 'novel' ? l10n.tr('import_novel') : l10n.tr('import_text'),
          isNovel: widget.type == 'novel',
          doSave: () async {
            final ok = await _doSave();
            if (ok) _savedFromFullscreen = true;
            return ok;
          },
          onPaste: _pasteAtCursor,
        ),
        fullscreenDialog: true,
      ),
    );
    // 全屏路由返回后，若已保存则关闭 Dialog
    if (_savedFromFullscreen && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<LocaleProvider>().l10n;
    final isNovel = widget.type == 'novel';

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(isNovel ? l10n.tr('import_novel') : l10n.tr('import_text'))),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: l10n.tr('expand'),
            onPressed: _enterFullscreen,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
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
    );
  }
}

/// 全屏文本编辑器：覆盖状态栏，编辑区占满整屏
class _TextEditorFullscreen extends StatefulWidget {
  final TextEditingController controller;
  final String title;
  final bool isNovel;
  /// 保存回调，返回是否保存成功（不负责 pop）
  final Future<bool> Function() doSave;
  final Future<void> Function() onPaste;

  const _TextEditorFullscreen({
    required this.controller,
    required this.title,
    required this.isNovel,
    required this.doSave,
    required this.onPaste,
  });

  @override
  State<_TextEditorFullscreen> createState() => _TextEditorFullscreenState();
}

class _TextEditorFullscreenState extends State<_TextEditorFullscreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 进入沉浸式全屏：隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 退出时恢复边到边模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ok = await widget.doSave();
      if (ok && mounted) {
        Navigator.pop(context);  // pop 全屏路由，返回 Dialog
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Column(
          children: [
            // 顶部工具栏：返回 / 粘贴 / 保存
            SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen_exit),
                    tooltip: l10n.tr('collapse'),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: l10n.tr('paste'),
                    onPressed: widget.onPaste,
                  ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
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
            ),
            // 编辑区：占据剩余空间
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom,
                  left: 16,
                  right: 16,
                ),
                child: TextField(
                  controller: widget.controller,
                  maxLines: null,
                  expands: true,
                  autofocus: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontSize: widget.isNovel ? 16 : 18,
                    height: widget.isNovel ? 1.8 : 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.isNovel ? l10n.tr('novel_hint') : l10n.tr('hint_text_or_emoji'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
