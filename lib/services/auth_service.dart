import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 用户认证服务 - 支持简单的用户管理和密码哈希
class AuthService {
  final Map<String, String> _users = {}; // username -> hashedPassword
  String? _currentUserId;
  
  /// 注册用户
  Future<bool> register(String username, String password) async {
    if (_users.containsKey(username)) {
      return false; // 用户已存在
    }
    
    final hashedPassword = _hashPassword(password);
    _users[username] = hashedPassword;
    _currentUserId = username;
    
    return true;
  }
  
  /// 用户登录
  Future<bool> login(String username, String password) async {
    final storedHash = _users[username];
    if (storedHash == null) {
      return false; // 用户不存在
    }
    
    final inputHash = _hashPassword(password);
    if (inputHash == storedHash) {
      _currentUserId = username;
      return true;
    }
    
    return false;
  }
  
  /// 用户登出
  void logout() {
    _currentUserId = null;
  }
  
  /// 获取当前用户
  String? getCurrentUser() {
    return _currentUserId;
  }
  
  /// 检查是否已登录
  bool isLoggedIn() {
    return _currentUserId != null;
  }
  
  /// 验证密码
  bool verifyPassword(String username, String password) {
    final storedHash = _users[username];
    if (storedHash == null) return false;
    
    final inputHash = _hashPassword(password);
    return inputHash == storedHash;
  }
  
  /// 哈希密码
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// 获取所有用户（仅用于调试）
  List<String> getAllUsers() {
    return _users.keys.toList();
  }
}
