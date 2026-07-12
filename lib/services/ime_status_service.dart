import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 检测和管理自定义输入法（IME）与无障碍服务的启用状态。
///
/// 仅 Android 原生端有效。Web / Windows 调用返回安全默认值。
class ImeStatusService {
  static const _channel = MethodChannel('mako_meme/native');

  /// IME 是否已在系统输入法列表中启用。
  static Future<bool> isImeEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isImeEnabled') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// IME 是否为当前默认输入法。
  static Future<bool> isImeDefault() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isImeDefault') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 无障碍服务是否已启用。
  static Future<bool> isAccessibilityEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 跳转到系统输入法设置页。
  static Future<bool> openImeSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openImeSettings') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 跳转到系统无障碍设置页。
  static Future<bool> openAccessibilitySettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAccessibilitySettings') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 弹出系统输入法切换选择器（快速切换到本应用 IME）。
  static Future<bool> showImePicker() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('showImePicker') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 写入 IME 主题配色（JSON），供输入法服务读取并应用。
  static Future<bool> updateImeTheme(String json) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('updateImeTheme', {'json': json}) ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
