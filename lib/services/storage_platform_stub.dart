// Web storage stub - no-op on non-web platforms
import 'dart:typed_data';

// IndexedDB stubs (no-op on non-web)
Future<void> initWebStorage() async {}
Future<void> webStorageSetJson(String key, dynamic value) async {}
Future<dynamic> webStorageGetJson(String key) async => null;
Future<void> webStorageSetBinary(String key, Uint8List bytes) async {}
Future<Uint8List?> webStorageGetBinary(String key) async => null;
Future<void> webStorageDelete(String key) async {}
