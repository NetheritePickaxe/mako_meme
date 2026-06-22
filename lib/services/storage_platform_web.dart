import 'dart:html' show window;

/// Web 端使用 dart:html 的 localStorage
String? webStorageGetItem(String key) => window.localStorage[key];
void webStorageSetItem(String key, String value) {
  window.localStorage[key] = value;
}
