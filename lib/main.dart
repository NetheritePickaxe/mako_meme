import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/database/database.dart';
import 'data/services/file_service.dart';
import 'data/services/preset_service.dart';
import 'data/repositories/sticker_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化预置数据
  final db = AppDatabase();
  final fileService = FileService();
  final repo = StickerRepository(db, fileService);
  final presetService = PresetService(repo);
  await presetService.initializeIfNeeded();

  runApp(
    const ProviderScope(
      child: MakoMemeApp(),
    ),
  );
}
