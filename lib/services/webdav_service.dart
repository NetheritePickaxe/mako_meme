import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// WebDAV 服务 - 支持文件上传/下载/列表/删除
class WebDavService {
  final String baseUrl;
  final String username;
  final String password;
  
  WebDavService({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      final response = await http.head(
        Uri.parse('$baseUrl/'),
        headers: _getAuthHeaders(),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 上传文件
  Future<bool> uploadFile(String remotePath, Uint8List bytes) async {
    try {
      final uri = Uri.parse('$baseUrl/$remotePath');
      final request = http.put(uri, body: bytes, headers: _getAuthHeaders());
      final response = await request;
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 下载文件
  Future<Uint8List?> downloadFile(String remotePath) async {
    try {
      final uri = Uri.parse('$baseUrl/$remotePath');
      final response = await http.get(uri, headers: _getAuthHeaders());
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取认证头
  String _getAuthHeader() {
    final credentials = '$username:$password';
    final encoded = base64.encode(utf8.encode(credentials));
    return 'Basic $encoded';
  }

  /// 获取认证头映射
  Map<String, String> _getAuthHeaders() {
    return {
      'Authorization': _getAuthHeader(),
    };
  }

  /// 生成远程路径
  String generateRemotePath(String localPath) {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final fileName = localPath.split('/').last;
    return 'mako_meme/$year/$month/$fileName';
  }
}
