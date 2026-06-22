import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart';
import '../../data/services/file_service.dart';
import '../../data/repositories/sticker_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final fileServiceProvider = Provider<FileService>((ref) {
  return FileService();
});

final stickerRepositoryProvider = Provider<StickerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final fs = ref.watch(fileServiceProvider);
  return StickerRepository(db, fs);
});

// ==================== Namespace ====================

final allNamespacesProvider = StreamProvider((ref) {
  final repo = ref.watch(stickerRepositoryProvider);
  return repo.watchAllNamespaces();
});

// ==================== Pack ====================

final allPacksProvider = StreamProvider((ref) {
  final repo = ref.watch(stickerRepositoryProvider);
  return repo.watchAllPacks();
});

final packsByNamespaceProvider =
    StreamProvider.family<List<StickerPackData>, String>(
  (ref, nsId) {
    final repo = ref.watch(stickerRepositoryProvider);
    return repo.watchPacksByNamespace(nsId);
  },
);

final searchPacksProvider =
    StreamProvider.family<List<StickerPackData>, String>(
  (ref, query) {
    final repo = ref.watch(stickerRepositoryProvider);
    return repo.searchPacks(query);
  },
);

/// 当前选中的命名空间 ID (null = 全部)
final activeNamespaceProvider = StateProvider<String?>((ref) => null);

/// 根据 activeNamespace 过滤后的包列表
final filteredPacksProvider = Provider((ref) {
  final nsId = ref.watch(activeNamespaceProvider);
  final packsAsync = nsId == null
      ? ref.watch(allPacksProvider)
      : ref.watch(packsByNamespaceProvider(nsId));
  return packsAsync;
});

// ==================== Sticker ====================

final stickersByPackProvider =
    StreamProvider.family<List<StickerData>, String>(
  (ref, packId) {
    final repo = ref.watch(stickerRepositoryProvider);
    return repo.watchStickersByPack(packId);
  },
);

final searchStickersProvider =
    StreamProvider.family<List<StickerData>, String>(
  (ref, query) {
    final repo = ref.watch(stickerRepositoryProvider);
    return repo.searchStickers(query);
  },
);
