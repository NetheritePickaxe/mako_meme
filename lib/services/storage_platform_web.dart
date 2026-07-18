// Web 端 IndexedDB 存储 — 基于 sembast
// 提供简单键值存储 + 二进制数据支持
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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
    debugPrint('[MakoWeb] setBinary ok: key=$key, bytes=${bytes.length}');
  } catch (e, st) {
    debugPrint('[MakoWeb] setBinary FAIL: key=$key, error=$e, st=$st');
  }
}

/// 获取二进制数据
Future<Uint8List?> webStorageGetBinary(String key) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store('images');
    final snapshot = await store.record(key).getSnapshot(db);
    if (snapshot != null) {
      final raw = (snapshot.value as Map)['bytes'];
      if (raw is Uint8List) {
        debugPrint('[MakoWeb] getBinary ok(Uint8List): key=$key, bytes=${raw.length}');
        return raw;
      }
      if (raw is List) {
        final converted = Uint8List.fromList(raw.cast<int>());
        debugPrint('[MakoWeb] getBinary ok(List→Uint8): key=$key, bytes=${converted.length}');
        return converted;
      }
      debugPrint('[MakoWeb] getBinary FAIL: key=$key, unexpected type=${raw.runtimeType}');
      return null;
    }
    debugPrint('[MakoWeb] getBinary MISS: key=$key (record not found)');
    return null;
  } catch (e, st) {
    debugPrint('[MakoWeb] getBinary ERROR: key=$key, error=$e, st=$st');
    return null;
  }
}

/// 删除
Future<void> webStorageDelete(String key) async {
  try {
    final db = await _factory.openDatabase('mako_meme_db');
    final store = stringMapStoreFactory.store('images');
    await store.record(key).delete(db);
    debugPrint('[MakoWeb] delete ok: key=$key');
  } catch (e, st) {
    debugPrint('[MakoWeb] delete FAIL: key=$key, error=$e, st=$st');
  }
}
