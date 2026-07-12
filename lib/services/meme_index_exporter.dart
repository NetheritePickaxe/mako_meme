import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/meme.dart';
import 'storage_service.dart';

/// 将 meme 索引导出给原生 ContentProvider，供 IME 进程读取。
///
/// 仅 Android 原生端有效。Web / Windows 调用为空操作。
class MemeIndexExporter {
  static const _channel = MethodChannel('mako_meme/native');

  final StorageService _storage;

  MemeIndexExporter(this._storage);

  /// 导出全部 meme 的精简索引（id/name/type/absPath/tags/folderId/textContent）。
  /// 图片类需要绝对路径，文字类只需 textContent。
  Future<void> exportAll(List<Meme> memes) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final list = <Map<String, dynamic>>[];
    for (final m in memes) {
      String absPath = '';
      if (m.isImageType && m.filePath.isNotEmpty) {
        absPath = _storage.getMemeAbsolutePath(m.filePath) ?? '';
      }
      list.add({
        'id': m.id,
        'name': m.name,
        'type': m.type,
        'absPath': absPath,
        'tags': m.tags,
        'folderId': m.folderId,
        'isFavorite': m.isFavorite,
        'mimeType': m.mimeType,
        'textContent': m.textContent,
        'width': m.width,
        'height': m.height,
      });
    }

    final json = jsonEncode(list);
    try {
      await _channel.invokeMethod<bool>('updateMemeIndex', {'json': json});
    } on PlatformException catch (_) {
      // 原生插件未注册（非 Android）— 忽略
    }
  }

  /// 清空索引（如用户登出）
  Future<void> clear() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('clearMemeIndex');
    } on PlatformException catch (_) {}
  }
}
