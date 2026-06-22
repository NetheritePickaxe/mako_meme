/// Web 存储 — 条件导出
/// 非 Web 平台使用存根；Web 平台使用 dart:html localStorage
export 'storage_platform_stub.dart'
    if (dart.library.html) 'storage_platform_web.dart';
