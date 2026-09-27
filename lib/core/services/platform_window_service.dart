import 'dart:io';

import 'package:flutter/services.dart';

/// Helper to obtain native platform window identifiers for modal parenting.
class PlatformWindowService {
  static const MethodChannel _channel = MethodChannel('dev.kawi/window');

  /// Retrieves the window handle formatted for the platform compositor/portal
  /// (e.g. `x11:0x<xid>` or `wayland:<handle>`).
  static Future<String?> getWindowHandle() async {
    if (!Platform.isLinux) return null;
    try {
      final handle = await _channel.invokeMethod<String>('getWindowHandle');
      return handle;
    } catch (_) {
      return null;
    }
  }
}
