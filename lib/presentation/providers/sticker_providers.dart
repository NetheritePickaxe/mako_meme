import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/services/file_service.dart';
import '../../data/repositories/sticker_repository.dart';

/// 数据库单例 provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// FileService provider
final fileServiceProvider = Provider<FileService>((ref) {
  return FileService();
});

/// StickerRepository provider
final stickerRepositoryProvider = Provider<StickerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final fs = ref.watch(fileServiceProvider);
  return StickerRepository(db, fs);
});

/// 所有表情包包列表
final allPacksProvider = StreamProvider((ref) {
  final repo = ref.watch(stickerRepositoryProvider);
  return repo.watchAllPacks();
});

/// 根据 packId 获取表情列表
final stickersByPackProvider = StreamProvider.family<List<StickerData>, String>(
  (ref, packId) {
    final repo = ref.watch(stickerRepositoryProvider);
    return repo.watchStickersByPack(packId);
  },
);

/// 全局搜索
final searchStickersProvider = StreamProvider.family<List<StickerData>, String>(
  (ref, query) {
    final repo = ref.watch(stickerRepositoryProvider);
    return repo.searchStickers(query);
  },
);
