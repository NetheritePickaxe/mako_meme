import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class L10n {
  final String languageCode;
  final Map<String, String> _messages;

  const L10n({required this.languageCode, required Map<String, String> messages})
      : _messages = messages;

  static Future<L10n> load(String langCode) async {
    try {
      final raw = await rootBundle.loadString('assets/l10n/$langCode.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final messages = json.map((k, v) => MapEntry(k, v.toString()));
      return L10n(languageCode: langCode, messages: messages);
    } catch (e) {
      return L10n(languageCode: langCode, messages: {});
    }
  }

  String tr(String key, {Map<String, String>? args}) {
    String value = _messages[key] ?? key;
    if (args == null) return value;
    args.forEach((k, v) {
      value = value.replaceAll('{$k}', v);
    });
    return value;
  }
}
