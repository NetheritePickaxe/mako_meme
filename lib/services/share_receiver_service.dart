import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/meme.dart';

/// 接收外部分享的服务（仅 Android/iOS 支持）
///
/// 在 main.dart 启动时调用 [init]，会：
/// 1. 处理冷启动时的初始分享 intent
/// 2. 监听 app 运行期间的新分享 intent
///
/// 收到的图片会转换为 [PlatformFile] 列表，通过 [onShared] 回调通知上层。
class ShareReceiverService {
  ShareReceiverService();

  final _instance = ReceiveSharingIntent.instance;
  Stream<List<SharedMediaFile>>? _stream;
  bool _initialized = false;

  /// 收到分享时的回调（在 root isolate 中触发）
  void Function(List<PlatformFile> files)? onShared;

  /// 初始化：处理冷启动 intent + 订阅运行时 intent
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // 1. 冷启动时获取初始分享
    try {
      final initial = await _instance.getInitialMedia();
      if (initial.isNotEmpty) {
        final files = _toPlatformFiles(initial);
        if (files.isNotEmpty) {
          onShared?.call(files);
        }
        // 通知原生已消费，避免下次启动重复触发
        await _instance.reset();
      }
    } catch (_) {}

    // 2. 监听运行时分享
    _stream ??= _instance.getMediaStream();
    _stream!.listen((List<SharedMediaFile> media) {
      final files = _toPlatformFiles(media);
      if (files.isNotEmpty) {
        onShared?.call(files);
      }
    });
  }

  /// 将 [SharedMediaFile] 列表转换为导入流程可用的 [PlatformFile] 列表
  /// 仅保留图片类型，跳过视频等其他类型
  List<PlatformFile> _toPlatformFiles(List<SharedMediaFile> media) {
    final result = <PlatformFile>[];
    for (final m in media) {
      // 仅处理图片类型
      if (m.type != SharedMediaType.image) continue;
      final path = m.path;
      if (path.isEmpty) continue;
      final name = _basename(path);
      final ext = _extension(name);
      // 只接收支持的扩展名（无扩展名时根据 mimeType 兜底为 jpg）
      final effectiveExt = Meme.supportedExtensions.contains(ext)
          ? ext
          : (m.mimeType?.startsWith('image/') == true ? 'jpg' : '');
      if (effectiveExt.isEmpty) continue;
      // 修正 name 以带上有效扩展名（部分 cache 文件无扩展名）
      final effectiveName = ext.isEmpty && effectiveExt.isNotEmpty
          ? '$name.$effectiveExt'
          : name;
      result.add(PlatformFile(
        name: effectiveName,
        path: path,
        // SharedMediaFile 不提供 size，导入时会从实际文件读取
        size: 0,
        bytes: null,
      ));
    }
    return result;
  }

  String _basename(String path) {
    final sep = path.contains('\\') ? '\\' : '/';
    final idx = path.lastIndexOf(sep);
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  /// 返回不带点的扩展名（如 "jpg"），无扩展名返回空字符串
  String _extension(String name) {
    final idx = name.lastIndexOf('.');
    return idx >= 0 ? name.substring(idx + 1).toLowerCase() : '';
  }
}
