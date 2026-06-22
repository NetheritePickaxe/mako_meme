import 'dart:io';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import '../database/database.dart';
import '../services/file_service.dart';

class StickerRepository {
  final AppDatabase _db;
  final FileService _fileService;
  final Uuid _uuid = const Uuid();

  StickerRepository(this._db, this._fileService);

  // ==================== Pack ====================

  Stream<List<StickerPackData>> watchAllPacks() => _db.watchAllPacks();

  Future<StickerPackData?> getPack(String id) => _db.getPack(id);

  Future<StickerPackData> createPack({
    required String name,
    String? description,
    String? iconPath,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.insertPack(StickerPacksCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      iconPath: Value(iconPath),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return (await _db.getPack(id))!;
  }

  Future<void> updatePack(String id, {
    String? name,
    String? description,
    String? iconPath,
  }) async {
    final pack = await _db.getPack(id);
    if (pack == null) return;
    await _db.updatePack(
      id,
      StickerPacksCompanion(
        id: Value(id),
        name: Value(name ?? pack.name),
        description: Value(description ?? pack.description),
        iconPath: Value(iconPath ?? pack.iconPath),
        createdAt: Value(pack.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deletePack(String id) async {
    // 先删除 pack 下所有 sticker 的文件
    final stickers = await _db.getStickersByPack(id);
    for (final s in stickers) {
      await _fileService.deleteFile(s.storedPath);
    }
    await _db.deletePack(id);
  }

  // ==================== Sticker ====================

  Stream<List<StickerData>> watchStickersByPack(String packId) =>
      _db.watchStickersByPack(packId);

  Stream<List<StickerData>> searchStickers(String query) =>
      _db.searchStickers(query);

  Future<StickerData> importSticker({
    required String packId,
    required String sourcePath,
    List<String> tags = const [],
  }) async {
    final id = _uuid.v4();
    final filename = sourcePath.split(Platform.pathSeparator).last;
    final mimeType = lookupMimeType(sourcePath) ?? 'image/png';
    final storedPath = await _fileService.importFile(sourcePath);
    final dims = await _fileService.getImageDimensions(storedPath);

    await _db.insertSticker(StickersCompanion(
      id: Value(id),
      packId: Value(packId),
      filename: Value(filename),
      storedPath: Value(storedPath),
      mimeType: Value(mimeType),
      width: Value(dims?.$1),
      height: Value(dims?.$2),
      tags: Value(tags.isEmpty ? null : tags.join(',')),
      createdAt: Value(DateTime.now()),
    ));
    return (await _db.getSticker(id))!;
  }

  Future<List<StickerData>> importStickers({
    required String packId,
    required List<String> sourcePaths,
    List<String> tags = const [],
  }) async {
    final results = <StickerData>[];
    for (final path in sourcePaths) {
      try {
        final sticker = await importSticker(
          packId: packId,
          sourcePath: path,
          tags: tags,
        );
        results.add(sticker);
      } catch (_) {
        // 跳过导入失败的文件
      }
    }
    return results;
  }

  Future<void> deleteSticker(String id) async {
    final sticker = await _db.getSticker(id);
    if (sticker != null) {
      await _fileService.deleteFile(sticker.storedPath);
      await _db.deleteSticker(id);
    }
  }

  Future<void> updateStickerTags(String id, List<String> tags) async {
    final sticker = await _db.getSticker(id);
    if (sticker == null) return;
    // 直接用 raw update
    final db = _db;
    await (db.update(db.stickers)..where((t) => t.id.equals(id))).write(
      StickersCompanion(
        tags: Value(tags.isEmpty ? null : tags.join(',')),
      ),
    );
  }

  Future<List<StickerData>> getStickersByPack(String packId) =>
      _db.getStickersByPack(packId);

  /// 构建 sticker 文件完整路径
  Future<String> stickerFullPath(String storedFilename) =>
      _fileService.fullPath(storedFilename);
}
