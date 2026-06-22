import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database/database.dart';
import '../../shared/widgets/sticker_image.dart';
import '../providers/sticker_providers.dart';

/// 全屏预览单个表情
class StickerPreviewScreen extends ConsumerWidget {
  final StickerData sticker;

  const StickerPreviewScreen({super.key, required this.sticker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(stickerRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              final bytes = await repo.stickerBytes(sticker.storedPath);
              if (bytes != null) {
                final temp = await _writeTempFile(bytes, sticker.mimeType);
                if (temp != null) {
                  await Share.shareXFiles([XFile(temp)]);
                }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: StickerImage(
          sticker: sticker,
          repo: repo,
          fit: BoxFit.contain,
          height: double.infinity,
          width: double.infinity,
        ),
      ),
      bottomNavigationBar: sticker.tags != null && sticker.tags!.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children: sticker.tags!
                      .split(',')
                      .map((tag) => Chip(
                            label: Text(tag,
                                style: const TextStyle(color: Colors.white)),
                            backgroundColor:
                                Colors.white.withAlpha(40),
                            side: BorderSide.none,
                          ))
                      .toList(),
                ),
              ),
            )
          : null,
    );
  }

  /// 写临时文件用于分享 (Web 上可能不支持)
  Future<String?> _writeTempFile(Uint8List bytes, String mimeType) async {
    try {
      final ext = mimeType.split('/').last;
      final dir = await _getTempDir();
      final path = '${dir.path}/share_$sticker.$ext';
      await File(path).writeAsBytes(bytes);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getTempDir() async {
    try {
      return await Directory.systemTemp.createTemp('mako_share_');
    } catch (_) {
      return Directory('/tmp'); // fallback
    }
  }
}
