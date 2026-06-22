// Web 端 localStorage 实现 — 只在 dart.library.html 可用时编译
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' show window;

/// Web 端使用 dart:html 的 localStorage
String? webStorageGetItem(String key) => window.localStorage[key];
void webStorageSetItem(String key, String value) {
  window.localStorage[key] = value;
}
