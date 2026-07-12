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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {
      _updateError(v);
      if (_error == null) {
        _updateSuggestions(v);
        _maybeShowHelp(v);
      } else {
        _suggestions = [];
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('搜索帮助'),
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
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 点击补全项时，替换当前正在输入的部分
  void _applySuggestion(SearchSuggestion s) {
    final text = _controller.text;
    final selection = _controller.selection;

    // 如果光标在末尾（常见情况），简化处理
    if (selection.baseOffset == text.length) {
      // 提取 / 之后，去掉方括号
      var afterSlash = text.substring(text.startsWith('/') ? 1 : 0);
      afterSlash = afterSlash.replaceAll('[', '').replaceAll(']', '');

      // 按逗号分割，取最后一部分
      final parts = SearchQuery.getSuggestionsRawParts(text);

      if (parts.length > 1) {
        // 替换最后一部分
        final before = parts.sublist(0, parts.length - 1).join(',');
        // 判断是否有方括号
        final hasBracket = text.contains('[');
        final prefix = text.startsWith('/') ? '/' : '';
        final openBracket = hasBracket ? '[' : '';
        final closeBracket = hasBracket ? ']' : '';
        final newText = '$prefix$openBracket$before,$s.insert$closeBracket';
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(offset: newText.length - (hasBracket ? 1 : 0));
      } else {
        // 只有一部分，整体替换
        final hasBracket = text.contains('[');
        final prefix = text.startsWith('/') ? '/' : '';
        final openBracket = hasBracket ? '[' : '';
        final closeBracket = hasBracket ? ']' : '';
        final newText = '$prefix$openBracket${s.insert}$closeBracket';
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(offset: newText.length - (hasBracket ? 1 : 0));
      }
    } else {
      // 光标不在末尾，简单追加
      _controller.text = text + s.insert;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }

    _onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.watch<LocaleProvider>().l10n;
    final hasError = _error != null;
    final errorColor = theme.colorScheme.error;

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
                hasError ? Icons.error_outline : Icons.search,
                color: hasError ? errorColor : theme.colorScheme.onSurfaceVariant,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () {
                        _controller.clear();
                        _suggestions = [];
                        _lastHelpShown = '';
                        _error = null;
                        widget.onSearch('');
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: hasError
                  ? errorColor.withValues(alpha: 0.08)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: hasError ? errorColor : theme.colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: hasError ? errorColor : theme.colorScheme.outline,
                  width: hasError ? 1.5 : 1,
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
            onSubmitted: (v) {
              if (_error == null) widget.onSearch(v);
            },
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
        // 补全建议列表（有错误时不显示）
        if (!hasError && _suggestions.isNotEmpty)
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
