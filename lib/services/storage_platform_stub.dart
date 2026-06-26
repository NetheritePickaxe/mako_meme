/// Web 存储存根 — 非 Web 平台返回 null/空操作
import 'dart:typed_data';

String? webStorageGetItem(String key) => null;
void webStorageSetItem(String key, String value) {}

// IndexedDB stubs (no-op on non-web)
Future<void> initWebStorage() async {}
Future<void> webStorageSetJson(String key, dynamic value) async {}
Future<dynamic> webStorageGetJson(String key) async => null;
dynamic webStorageGetJsonSync(String key) => null;
Future<void> webStorageSetBinary(String key, Uint8List bytes) async {}
Future<Uint8List?> webStorageGetBinary(String key) async => null;
Future<void> webStorageDelete(String key) async {}
Future<void> webStorageClear(String store) async {}
Future<List<String>> webStorageGetAllKeys(String store) async => [];
Future<int> webStorageUsedBytes() async => 0;
