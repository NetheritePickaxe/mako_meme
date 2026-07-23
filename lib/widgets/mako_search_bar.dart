import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import '../providers/meme_provider.dart';
import '../services/search_query.dart';

class MakoSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;
  const MakoSearchBar({super.key, required this.onSearch});

  @override
  State<MakoSearchBar> createState() => _MakoSearchBarState();
}

class _MakoSearchBarState extends State<MakoSearchBar> {
  final _controller = TextEditingController();
  List<SearchSuggestion> _suggestions = [];
  String _lastHelpShown = '';
  String? _error;
  // 仅在用户按下回车尝试执行后才显示红色错误提示，输入过程中不报红
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {
      // 输入过程中隐藏错误提示，等用户再次回车时才重新检查显示
      _showError = false;
      _updateError(v);
      // 始终更新补全建议：即使有错误，也展示可用的补全项帮助用户完成输入
      // 这样用户输入 /tag 时即使格式不完整也能看到 add/remove 等补全
      _updateSuggestions(v);
      if (_error == null) {
        _maybeShowHelp(v);
      }
    });
    // 有错误时不触发搜索（保持上次结果）
    if (_error == null) {
      widget.onSearch(v);
    }
  }

  /// 校验语法，有错时设置 _error
  void _updateError(String v) {
    if (v.trim().isEmpty || !v.trim().startsWith('/')) {
      _error = null;
      return;
    }
    final prov = context.read<MemeProvider>();
    _error = SearchQuery.validate(v, prov.folders);
  }

  void _updateSuggestions(String v) {
    final prov = context.read<MemeProvider>();
    _suggestions = SearchQuery.getSuggestions(v, prov.allTags, prov.folders);
  }

  void _maybeShowHelp(String v) {
    // 完整帮助
    if (SearchQuery.isHelpRequest(v)) {
      if (_lastHelpShown != v) {
        _lastHelpShown = v;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showHelpDialog(SearchQuery.generateHelpText());
        });
      }
      return;
    }
    // 单命令帮助
    final cmd = SearchQuery.isCommandHelpRequest(v);
    if (cmd != null) {
      final key = '/$cmd ?';
      if (_lastHelpShown != key) {
        _lastHelpShown = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showHelpDialog(SearchQuery.generateCommandHelpText(cmd));
        });
      }
      return;
    }
    _lastHelpShown = '';
  }

  void _showHelpDialog(String text) {
    final theme = Theme.of(context);
    final l10n = context.read<LocaleProvider>().l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(l10n.tr('search_help_title')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('close')),
          ),
        ],
      ),
    );
  }

  /// 判断当前输入是否为命令模式（/ 开头且解析为 CommandSearch）
  bool _isCommandMode(String v) {
    final q = v.trim();
    if (!q.startsWith('/')) return false;
    final prov = context.read<MemeProvider>();
    return SearchQuery.parse(q, prov.folders) is CommandSearch;
  }

  /// 点击补全项时，替换当前正在输入的最后一个片段
  void _applySuggestion(SearchSuggestion s) {
    final text = _controller.text;
    final q = text.trim();

    String newText;
    if (q.startsWith('/')) {
      // 命令模式：按空白拆分，替换最后一个片段
      final parts = text.split(RegExp(r'\s+'));
      if (parts.isEmpty) {
        newText = s.insert;
      } else {
        parts[parts.length - 1] = s.insert;
        newText = parts.join(' ');
      }
    } else if (q.startsWith('[')) {
      // 选择器模式：按逗号拆分（忽略 {}），替换最后一个片段
      final parts = SearchQuery.getSuggestionsRawParts(text);
      if (parts.length <= 1) {
        newText = '[${s.insert}]';
      } else {
        final before = parts.sublist(0, parts.length - 1).join(',');
        newText = '[$before,${s.insert}]';
      }
    } else {
      // 普通模式：#tag / @folder 补全支持逗号多值
      final textTrimmed = _controller.text;
      final segments = textTrimmed.split(',');
      final last = segments.last.trim();
      if (last.startsWith('#') || last.startsWith('@')) {
        final lastComma = textTrimmed.lastIndexOf(',');
        if (lastComma == -1) {
          newText = s.insert;
        } else {
          newText = '${textTrimmed.substring(0, lastComma + 1)}${s.insert}';
        }
      } else {
        newText = s.insert;
      }
    }

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newText.length);
    _onChanged(_controller.text);
  }

  Future<void> _onSubmitted(String v) async {
    // 重新校验一次（防止 _onChanged 后文本被补全改过）
    _updateError(v);
    if (_error != null) {
      // 回车后才显示红色错误提示
      setState(() {
        _showError = true;
      });
      return;
    }
    final q = v.trim();
    if (q.isEmpty) {
      widget.onSearch(v);
      return;
    }

    // 命令模式：执行命令
    if (_isCommandMode(q)) {
      final prov = context.read<MemeProvider>();
      final l10n = context.read<LocaleProvider>().l10n;
      final msg = prov.executeCommand(q);
      // 清空搜索框
      _controller.clear();
      _suggestions = [];
      _lastHelpShown = '';
      _error = null;
      _showError = false;
      widget.onSearch('');
      setState(() {});
      if (mounted && msg != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tr(msg.key, args: msg.args)),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    widget.onSearch(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.watch<LocaleProvider>().l10n;
    // 仅在用户回车尝试执行后才显示红色错误 UI，输入过程中不报红
    final hasError = _showError && _error != null;
    final errorColor = theme.colorScheme.error;
    final isCmd = _isCommandMode(_controller.text);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: l10n.tr('search_hint'),
              hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              prefixIcon: Icon(
                hasError
                    ? Icons.error_outline
                    : (isCmd ? Icons.terminal : Icons.search),
                color: hasError
                    ? errorColor
                    : (isCmd ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () {
                        _controller.clear();
                        _suggestions = [];
                        _lastHelpShown = '';
                        _error = null;
                        _showError = false;
                        widget.onSearch('');
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: hasError
                  ? errorColor.withValues(alpha: 0.08)
                  : (isCmd
                      ? theme.colorScheme.primary.withValues(alpha: 0.06)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: hasError
                      ? errorColor
                      : (isCmd ? theme.colorScheme.primary : theme.colorScheme.outline),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: hasError
                      ? errorColor
                      : (isCmd ? theme.colorScheme.primary : theme.colorScheme.outline),
                  width: isCmd || hasError ? 1.5 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: hasError ? errorColor : theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            style: TextStyle(color: theme.colorScheme.onSurface),
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
        // 错误提示
        if (hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 16, 4),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: errorColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: errorColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // 补全建议列表（即使有错误也显示，帮助用户完成输入）
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) {
                final s = _suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(s.display, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface)),
                  subtitle: s.description != null
                      ? Text(s.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant))
                      : null,
                  onTap: () => _applySuggestion(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
