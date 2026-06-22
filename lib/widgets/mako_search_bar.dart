import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: '搜索表情（用 #前缀 搜索标签）',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); widget.onSearch(''); })
              : null,
        ),
        onChanged: (v) { setState(() {}); widget.onSearch(v); },
        onSubmitted: widget.onSearch,
      ),
    );
  }
}
