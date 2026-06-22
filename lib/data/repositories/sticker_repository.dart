import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  // ==================== Namespace ====================

  Stream<List<NamespaceData>> watchAllNamespaces() =>
      _db.watchAllNamespaces();

  Future<NamespaceData> createNamespace({
    required String name,
    String? icon,
    String? color,
  }) async {
    final id = _uuid.v4();
    await _db.insertNamespace(NamespacesCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      sortOrder: const Value(0),
      createdAt: Value(DateTime.now()),
    ));
    return (await _db.getNamespace(id))!;
  }

  Future<void> deleteNamespace(String id) => _db.deleteNamespace(id);

  // ==================== Pack ====================

  Stream<List<StickerPackData>> watchAllPacks() => _db.watchAllPacks();

  Stream<List<StickerPackData>> watchPacksByNamespace(String nsId) =>
      _db.watchPacksByNamespace(nsId);

  Stream<List<StickerPackData>> searchPacks(String query) =>
      _db.searchPacks(query);

  Future<StickerPackData?> getPack(String id) => _db.getPack(id);

  Future<StickerPackData> createPack({
    required String name,
    String? description,
    String? iconPath,
    String? namespaceId,
    List<String> tags = const [],
    Map<String, dynamic>? metadata,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.insertPack(StickerPacksCompanion(
      id: Value(id),
      namespaceId: Value(namespaceId),
      name: Value(name),
      description: Value(description),
      iconPath: Value(iconPath),
      tags: Value(tags.isEmpty ? null : tags.join(',')),
      metadata: Value(metadata != null ? jsonEncode(metadata) : null),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return (await _db.getPack(id))!;
  }

  Future<void> updatePack(String id, {
    String? name,
    String? description,
    String? iconPath,
    String? namespaceId,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    final pack = await _db.getPack(id);
    if (pack == null) return;
    await _db.updatePack(
      id,
      StickerPacksCompanion(
        id: Value(id),
        namespaceId: Value(namespaceId ?? pack.namespaceId),
        name: Value(name ?? pack.name),
        description: Value(description ?? pack.description),
        iconPath: Value(iconPath ?? pack.iconPath),
        tags: Value(tags != null ? (tags.isEmpty ? null : tags.join(',')) : pack.tags),
        metadata: Value(metadata != null ? jsonEncode(metadata) : pack.metadata),
        createdAt: Value(pack.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deletePack(String id) async {
    final stickers = await _db.getStickersByPack(id);
    for (final s in stickers) {
      await _fileService.deleteFile(s.storedPath);
    }
    await _db.deletePack(id);
  }

  /// 同步 metadata 中的 tags 到 tags 字段
  Future<void> syncPackTagsFromMetadata(String packId) async {
    final pack = await _db.getPack(packId);
    if (pack?.metadata == null) return;
    try {
      final meta = jsonDecode(pack!.metadata!) as Map<String, dynamic>;
      if (meta.containsKey('tags') && meta['tags'] is List) {
        final tagList = (meta['tags'] as List).cast<String>();
        final db = _db;
        await (db.update(db.stickerPacks)..where((t) => t.id.equals(packId))).write(
          StickerPacksCompanion(tags: Value(tagList.isEmpty ? null : tagList.join(','))),
        );
      }
    } catch (_) {}
  }

  // ==================== JSON Export / Import ====================

  /// 导出表情包为 JSON Map
  Future<Map<String, dynamic>> exportPackToJson(String packId) async {
    final pack = await _db.getPack(packId);
    if (pack == null) return {};

    final stickers = await _db.getStickersByPack(packId);
    final ns = pack.namespaceId != null
        ? await _db.getNamespace(pack.namespaceId!)
        : null;

    return {
      'name': pack.name,
      'description': pack.description,
      'namespace': ns?.name,
      'tags': pack.tags?.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList() ?? [],
      'metadata': pack.metadata != null ? jsonDecode(pack.metadata!) : {},
      'stickerCount': stickers.length,
      'stickers': stickers.map((s) => {
        'filename': s.filename,
        'mimeType': s.mimeType,
        'tags': s.tags?.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList() ?? [],
        'width': s.width,
        'height': s.height,
      }).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  /// 导出所有数据为 JSON
  Future<Map<String, dynamic>> exportAllToJson() async {
    final namespaces = await _db.watchAllNamespaces().first;
    final packs = await _db.watchAllPacks().first;

    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'namespaces': namespaces.map((n) => {
        'id': n.id,
        'name': n.name,
        'icon': n.icon,
        'color': n.color,
      }).toList(),
      'packs': packs.map((p) => p.id).toList(),
      // 详细导出需逐个 pack 调用 exportPackToJson
    };
  }

  /// 从 JSON 恢复 pack 标签和 metadata
  Future<void> applyPackMetadata(String packId, Map<String, dynamic> json) async {
    final tags = json['tags'] is List ? (json['tags'] as List).cast<String>() : <String>[];
    final metadata = json['metadata'] is Map ? json['metadata'] as Map<String, dynamic> : null;
    await updatePack(packId, tags: tags, metadata: metadata);
    final db = _db;
    await (db.update(db.stickerPacks)..where((t) => t.id.equals(packId))).write(
      StickerPacksCompanion(
        tags: Value(tags.isEmpty ? null : tags.join(',')),
        metadata: Value(metadata != null ? jsonEncode(metadata) : null),
      ),
    );
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
    Uint8List? bytes,
  }) async {
    final id = _uuid.v4();
    final filename = sourcePath.split(Platform.pathSeparator).last;
    final mimeType = lookupMimeType(sourcePath) ?? 'image/png';
    final storedPath = await _fileService.importFile(sourcePath, bytes: bytes);
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
    List<Uint8List?>? bytesList,
    List<String> tags = const [],
  }) async {
    final results = <StickerData>[];
    for (var i = 0; i < sourcePaths.length; i++) {
      try {
        final sticker = await importSticker(
          packId: packId,
          sourcePath: sourcePaths[i],
          tags: tags,
          bytes: bytesList != null && i < bytesList.length ? bytesList[i] : null,
        );
        results.add(sticker);
      } catch (_) {}
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
    final db = _db;
    await (db.update(db.stickers)..where((t) => t.id.equals(id))).write(
      StickersCompanion(
        tags: Value(tags.isEmpty ? null : tags.join(',')),
      ),
    );
  }

  Future<List<StickerData>> getStickersByPack(String packId) =>
      _db.getStickersByPack(packId);

  Future<String> stickerFullPath(String storedFilename) =>
      _fileService.fullPath(storedFilename);

  Future<Uint8List?> stickerBytes(String storedFilename) =>
      _fileService.readBytes(storedFilename);
}
