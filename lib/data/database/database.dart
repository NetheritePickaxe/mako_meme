import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Namespaces, StickerPacks, Stickers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(namespaces);
            await m.addColumn(stickerPacks, stickerPacks.namespaceId);
            await m.addColumn(stickerPacks, stickerPacks.tags);
            await m.addColumn(stickerPacks, stickerPacks.metadata);
          }
        },
      );

  // ==================== Namespace ====================

  Stream<List<NamespaceData>> watchAllNamespaces() =>
      select(namespaces).watch();

  Future<NamespaceData?> getNamespace(String id) =>
      (select(namespaces)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertNamespace(NamespacesCompanion ns) =>
      into(namespaces).insert(ns);

  Future<int> deleteNamespace(String id) =>
      (delete(namespaces)..where((t) => t.id.equals(id))).go();

  // ==================== StickerPack ====================

  /// 获取某命名空间下所有包
  Stream<List<StickerPackData>> watchPacksByNamespace(String nsId) =>
      (select(stickerPacks)..where((t) => t.namespaceId.equals(nsId))).watch();

  /// 获取所有包（按命名空间分组用）
  Stream<List<StickerPackData>> watchAllPacks() => select(stickerPacks).watch();

  Future<StickerPackData?> getPack(String id) =>
      (select(stickerPacks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertPack(StickerPacksCompanion pack) =>
      into(stickerPacks).insert(pack);

  Future<bool> updatePack(String id, StickerPacksCompanion pack) =>
      update(stickerPacks).replace(pack.copyWith(id: Value(id)));

  Future<int> deletePack(String id) =>
      (delete(stickerPacks)..where((t) => t.id.equals(id))).go();

  /// 按包标签搜索
  Stream<List<StickerPackData>> searchPacks(String query) {
    final q = '%$query%';
    return (select(stickerPacks)
          ..where((t) => t.name.like(q) | t.tags.like(q)))
        .watch();
  }

  // ==================== Sticker ====================

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

  static QueryExecutor _openConnection() {
    if (kIsWeb) {
      return driftDatabase(
        name: 'mako_meme.db',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );
    }
    return driftDatabase(name: 'mako_meme.db');
  }
}
