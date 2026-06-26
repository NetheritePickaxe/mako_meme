import 'dart:convert';
import 'dart:io';

Future<void> platformLoadConfig(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    await file.writeAsString('''{
  "admin": {
    "username": "",
    "password": ""
  }
}
''');
  }
}

Future<Map<String, dynamic>?> platformReadConfig(String path) async {
  final file = File(path);
  final raw = await file.readAsString();
  return jsonDecode(raw) as Map<String, dynamic>;
}
