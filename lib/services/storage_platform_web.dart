// Web 端 IndexedDB 存储 — 基于 sembast
// 提供简单键值存储 + 二进制数据支持
import 'dart:convert';
import 'dart:typed_data';
import 'package:sembast_web/sembast_web.dart';

final DatabaseFactory _factory = databaseFactoryWeb;

/// 初始化 IndexedDB
Future<void> initWebStorage() async {
  try {
    await _factory.openDatabase('mako_meme_db');
  } catch (_) {}
}

/// 存入 JSON
Future<void> webStorageSetJson(String key, dynamic value) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store(key);
    await store.record('data').put(db, {'value': jsonEncode(value)});
  } catch (_) {}
}

/// 获取 JSON
Future<dynamic> webStorageGetJson(String key) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store(key);
    final snapshot = await store.record('data').getSnapshot(db);
    if (snapshot != null) {
      return (snapshot.value as Map)['value'] as String?;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 存入二进制数据
Future<void> webStorageSetBinary(String key, Uint8List bytes) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store('images');
    await store.record(key).put(db, {'path': key, 'bytes': bytes});
  } catch (_) {}
}

/// 获取二进制数据
Future<Uint8List?> webStorageGetBinary(String key) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store('images');
    final snapshot = await store.record(key).getSnapshot(db);
    if (snapshot != null) {
      return (snapshot.value as Map)['bytes'] as Uint8List?;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 删除
Future<void> webStorageDelete(String key) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store('settings');
    await store.record(key).delete(db);
  } catch (_) {}
}

/// 清空 store
Future<void> webStorageClear(String storeName) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store(storeName);
    await store.drop(db);
  } catch (_) {}
}

/// 获取所有 keys
Future<List<String>> webStorageGetAllKeys(String storeName) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store(storeName);
    final records = await store.find(db);
    return records.map((r) => r.key.toString()).toList();
  } catch (_) {
    return [];
  }
}

/// 估算已用字节数
Future<int> webStorageUsedBytes() async {
  int total = 0;
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store('settings');
    final records = await store.find(db);
    for (final record in records) {
      final map = record.value as Map;
      for (final entry in map.entries) {
        if (entry.value is String) {
          total += (entry.value as String).length * 2;
        }
      }
    }
  } catch (_) {}
  return total;
}
