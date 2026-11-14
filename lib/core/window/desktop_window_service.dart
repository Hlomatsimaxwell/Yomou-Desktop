import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Syncs the app's effective brightness with GTK so the header bar / window
/// chrome stays in step with the app theme (and the system theme on Linux).
///
/// Android has its own window chrome and is untouched; web is not supported.
class DesktopWindowService {
  DesktopWindowService._();

  static const _channel = MethodChannel('com.hlomatsi.yomou/window');

  static bool get _isLinux => !kIsWeb && Platform.isLinux;

  /// Tell GTK whether the app is using a dark theme so the title bar/header
  /// bar follows along. Best-effort: the native channel is Linux-only.
  static Future<void> setDarkTheme(bool dark) async {
    if (!_isLinux) return;
    try {
      await _channel.invokeMethod<bool>('setDarkTheme', {'dark': dark});
    } catch (_) {
      // GTK integration is best-effort; never block the app on it.
    }
  }
}
