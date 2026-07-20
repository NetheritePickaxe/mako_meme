// PDF 在浏览器新标签页打开 — 条件导出
// 非 Web 平台使用存根（原生走 launchUrl）；Web 平台使用 dart:html 打开 blob URL
export 'pdf_opener_stub.dart'
    if (dart.library.html) 'pdf_opener_web.dart';
