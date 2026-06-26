import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// 配置加载器
class ConfigLoader {
  static Map<String, dynamic>? _config;

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('assets/config.json');
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
    final storedHash = admin?['password_hash'] as String?;

    if (storedUsername == null || (storedHash ?? '').isEmpty) return false;
    if (username != storedUsername) return false;

    final inputHash = sha256.convert(utf8.encode(password)).toString();
    if (inputHash != storedHash) return false;

    _loggedInUsername = username;
    return true;
  }

  /// 登出
  void logout() {
    _loggedInUsername = null;
  }
}
