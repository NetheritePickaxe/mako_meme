import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/database/database.dart';
import 'data/services/file_service.dart';
import 'data/services/preset_service.dart';
import 'data/repositories/sticker_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化预置数据 (Web 环境可能不支持 Canvas/File IO, 优雅降级)
  try {
    final db = AppDatabase();
    final fileService = FileService();
    final repo = StickerRepository(db, fileService);
    final presetService = PresetService(repo);
    await presetService.initializeIfNeeded();
  } catch (e) {
    debugPrint('Preset initialization skipped: $e');
  }

  runApp(
    const ProviderScope(
      child: MakoMemeApp(),
    ),
  );
}
