import 'dart:convert';
import 'dart:html' as html;

Future<void> platformLoadConfig(String path) async {}

Future<Map<String, dynamic>?> platformReadConfig(String path) async {
  try {
    final stored = html.window.localStorage[path];
    if (stored != null && stored.isNotEmpty) {
      return jsonDecode(stored) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {};
}
