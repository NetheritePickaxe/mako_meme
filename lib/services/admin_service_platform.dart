import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 解析可写的配置文件路径。
///
/// Android 的工作目录是只读的，写入相对路径 `config.json` 会抛出
/// `FileSystemException`，导致 `main()` 在 `runApp` 之前中断，
/// 表现为应用卡在开屏界面。这里改用 `getApplicationSupportDirectory`
/// 拿到一个可写目录，把配置文件放进去。
Future<File> _resolveConfigFile(String path) async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, path));
}

Future<void> platformLoadConfig(String path) async {
  try {
    final file = await _resolveConfigFile(path);
    if (!file.existsSync()) {
      await file.create(recursive: true);
      await file.writeAsString('''{
  "admin": {
    "username": "",
    "password": ""
  }
}
''');
    }
  } catch (_) {
    // 配置写入失败不应阻塞应用启动。
  }
}

Future<Map<String, dynamic>?> platformReadConfig(String path) async {
  try {
    final file = await _resolveConfigFile(path);
    if (!file.existsSync()) return {};
    final raw = await file.readAsString();
    if (raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}
