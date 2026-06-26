import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// 配置加载器 — 从 config.json 读取管理员配置
class ConfigLoader {
  static Map<String, dynamic>? _config;
  static const String _configPath = 'config.json';

  static Future<void> load() async {
    final file = File(_configPath);
    if (!file.existsSync()) {
      // 首次启动生成默认配置
      await file.writeAsString('''{
  "admin": {
    "username": "",
    "password": ""
  }
}
''');
    }
    try {
      final raw = await file.readAsString();
      _config = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _config = {};
    }
  }

  static Map<String, dynamic>? get config => _config;
}

/// 管理员服务 — 只支持管理员登录
class AdminService {
  String? _loggedInUsername;

  /// 检查是否已登录管理员
  bool get isLoggedIn => _loggedInUsername != null;
  String? get loggedInUsername => _loggedInUsername;

  /// 登录管理员
  Future<bool> login(String username, String password) async {
    final config = ConfigLoader.config;
    final admin = config?['admin'] as Map<String, dynamic>?;
    final storedUsername = admin?['username'] as String?;
    final storedPassword = admin?['password'] as String?;

    if (storedUsername == null || (storedPassword ?? '').isEmpty) return false;
    if (username != storedUsername) return false;

    final inputHash = sha256.convert(utf8.encode(password)).toString();
    final storedHash = sha256.convert(utf8.encode(storedPassword!)).toString();
    if (inputHash != storedHash) return false;

    _loggedInUsername = username;
    return true;
  }

  /// 登出
  void logout() {
    _loggedInUsername = null;
  }
}
