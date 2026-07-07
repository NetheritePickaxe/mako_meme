import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';

class MakoSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;
  const MakoSearchBar({super.key, required this.onSearch});

  @override
  State<MakoSearchBar> createState() => _MakoSearchBarState();
}

class _MakoSearchBarState extends State<MakoSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.watch<LocaleProvider>().l10n;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: l10n.tr('search_hint'),
          hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(icon: Icon(Icons.clear, color: theme.colorScheme.onSurfaceVariant), onPressed: () { _controller.clear(); widget.onSearch(''); })
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: theme.colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: theme.colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
        ),
        style: TextStyle(color: theme.colorScheme.onSurface),
        onChanged: (v) { setState(() {}); widget.onSearch(v); },
        onSubmitted: widget.onSearch,
      ),
    );
  }
}
