import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

String get picturesDirectory {
  if (kIsWeb) return '';
  if (Platform.isWindows) {
    return '${Platform.environment['USERPROFILE']}\\Pictures';
  }
  if (Platform.isLinux) {
    return '${Platform.environment['HOME']}/Pictures';
  }
  if (Platform.isMacOS) {
    return '${Platform.environment['HOME']}/Pictures';
  }
  return '';
}
