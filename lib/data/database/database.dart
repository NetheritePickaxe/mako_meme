import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [StickerPacks, Stickers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// 初始化时创建数据库并执行迁移
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );

  // --- StickerPack queries ---

  Stream<List<StickerPackData>> watchAllPacks() => select(stickerPacks).watch();

  Future<StickerPackData?> getPack(String id) =>
      (select(stickerPacks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertPack(StickerPacksCompanion pack) =>
      into(stickerPacks).insert(pack);

  Future<bool> updatePack(String id, StickerPacksCompanion pack) =>
      update(stickerPacks).replace(pack.copyWith(id: Value(id)));

  Future<int> deletePack(String id) =>
      (delete(stickerPacks)..where((t) => t.id.equals(id))).go();

  // --- Sticker queries ---

  Stream<List<StickerData>> watchStickersByPack(String packId) =>
      (select(stickers)..where((t) => t.packId.equals(packId))).watch();

  Stream<List<StickerData>> searchStickers(String query) {
    final q = '%$query%';
    return (select(stickers)..where((t) => t.tags.like(q) | t.filename.like(q)))
        .watch();
  }

  Future<StickerData?> getSticker(String id) =>
      (select(stickers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertSticker(StickersCompanion sticker) =>
      into(stickers).insert(sticker);

  Future<int> deleteSticker(String id) =>
      (delete(stickers)..where((t) => t.id.equals(id))).go();

  Future<List<StickerData>> getStickersByPack(String packId) =>
      (select(stickers)..where((t) => t.packId.equals(packId))).get();

  /// 获取所有表情（带 pack join，用于全局搜索）
  Stream<List<TypedResult>> watchAllStickers() {
    final query = select(stickers).join([
      leftOuterJoin(stickerPacks, stickerPacks.id.equalsExp(stickers.packId)),
    ]);
    return query.watch();
  }

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'mako_meme.db');
}
