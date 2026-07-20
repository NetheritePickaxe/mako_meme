import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/locale_provider.dart';
import 'package:provider/provider.dart';

/// 文本/小说编辑页面
/// - 以全屏路由形式呈现（覆盖状态栏）
/// - 默认紧凑模式：居中卡片式编辑区
/// - 点击展开按钮切换为真正全屏：AppBar 隐藏，编辑区占满整屏
/// - 仅纯文本编辑，标题用首行/前 30 字符自动生成
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
    // 退出时恢复边到边模式（防止沉浸式残留）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  /// 粘贴剪贴板内容：插入到光标位置
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

  void _enterFullscreen() {
    setState(() => _expanded = true);
    // 隐藏系统状态栏与导航栏，实现真正沉浸式全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    // 先恢复系统 UI，再切换状态，避免界面闪烁
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.read<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final isNovel = widget.type == 'novel';
    final isDark = theme.brightness == Brightness.dark;

    if (_expanded) {
      // 真正全屏：隐藏状态栏，无 AppBar，编辑区占满整屏
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          // 无 AppBar，body 直接延伸到状态栏区域
          extendBodyBehindAppBar: true,
          body: Column(
            children: [
              // 顶部工具栏（退出全屏 / 粘贴 / 保存）—— SafeArea 避开状态栏
              SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.fullscreen_exit),
                      tooltip: l10n.tr('collapse'),
                      onPressed: _exitFullscreen,
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: l10n.tr('paste'),
                      onPressed: _pasteAtCursor,
                    ),
                    const Spacer(),
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
                    controller: _textCtrl,
                    maxLines: null,
                    expands: true,
                    autofocus: true,
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
            ],
          ),
        ),
      );
    }

    // 紧凑模式：全屏路由 + 居中卡片
    return Scaffold(
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.95),
      appBar: AppBar(
        title: Text(isNovel ? l10n.tr('import_novel') : l10n.tr('import_text')),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: l10n.tr('expand'),
            onPressed: _enterFullscreen,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 240,
                  child: TextField(
                    controller: _textCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    autofocus: true,
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
        ),
      ),
    );
  }
}
