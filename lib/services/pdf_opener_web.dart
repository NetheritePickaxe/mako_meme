// PDF 在浏览器新标签页打开 — Web 实现
// 使用 Blob + URL.createObjectURL + window.open 直接在浏览器中预览 PDF
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// 将 PDF 字节以 application/pdf Blob 形式在新标签页打开。
/// 成功打开返回 true，失败返回 false（调用方可回退到下载提示）。
Future<bool> openPdfInNewTab(Uint8List bytes, String fileName) async {
  try {
    final blob = html.Blob(
      [bytes],
      'application/pdf',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    // 使用 window.open 在新标签页打开 PDF；命名窗口避免被某些浏览器拦截
    js.context.callMethod('open', [url, '_blank']);
    // 延迟释放对象 URL，给浏览器加载时间
    Future.delayed(const Duration(seconds: 60), () {
      try {
        html.Url.revokeObjectUrl(url);
      } catch (_) {}
    });
    return true;
  } catch (_) {
    return false;
  }
}
