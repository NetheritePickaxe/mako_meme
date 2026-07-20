// PDF 打开存根 — 非 Web 平台不用此入口（走 launchUrl）
import 'dart:typed_data';

/// 在 Web 上以新标签页打开 PDF。原生端返回 false，由调用方走 launchUrl。
Future<bool> openPdfInNewTab(Uint8List bytes, String fileName) async {
  return false;
}
