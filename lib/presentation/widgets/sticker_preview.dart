import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database/database.dart';
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
              final path = await repo.stickerFullPath(sticker.storedPath);
              await Share.shareXFiles([XFile(path)]);
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.pop(context);
              // 回退到上层页面后会触发标签编辑
              // 简单做法：直接在这里编辑
            },
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<String>(
          future: repo.stickerFullPath(sticker.storedPath),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            final file = File(snapshot.data!);
            if (!file.existsSync()) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, size: 64, color: Colors.white54),
                  SizedBox(height: 8),
                  Text('文件不存在', style: TextStyle(color: Colors.white54)),
                ],
              );
            }
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(file, fit: BoxFit.contain),
            );
          },
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
}
