import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseUrl;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseUrl,
  });
}

class UpdateService {
  static const _repo = 'NetheritePickaxe/mako_meme';

  Future<UpdateInfo?> check() async {
    try {
      final uri = Uri.parse('https://api.github.com/repos/$_repo/releases/latest');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'mako_meme',
      });
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseUrl = data['html_url'] as String? ?? '';
      final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      final pkg = await PackageInfo.fromPlatform();
      final current = pkg.version;
      if (_compareVersion(version, current) <= 0) return null;

      final assets = data['assets'] as List? ?? [];
      String? downloadUrl;
      if (!kIsWeb) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('-arm64-v8a.apk') || name.endsWith('-setup.exe')) {
            downloadUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }
      downloadUrl ??= releaseUrl;

      return UpdateInfo(version: version, downloadUrl: downloadUrl, releaseUrl: releaseUrl);
    } catch (_) {
      return null;
    }
  }

  int _compareVersion(String a, String b) {
    final partsA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  static Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
