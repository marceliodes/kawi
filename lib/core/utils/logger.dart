import 'package:flutter/foundation.dart';

/// Centralized structured logger for Kawi.
///
/// Provides standard logging levels ([d], [i], [w], [e]) and ensures
/// debug and info logs are strictly guarded by [kDebugMode] using [debugPrint]
/// to eliminate log noise and string formatting overhead in release builds.
abstract final class AppLogger {
  const AppLogger._();

  /// Logs a debug message. Strictly guarded by [kDebugMode].
  static void d(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// Logs an informational message. Strictly guarded by [kDebugMode].
  static void i(String message) {
    if (kDebugMode) {
      debugPrint('[INFO] $message');
    }
  }

  /// Logs a warning message with optional error and stack trace.
  static void w(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      final buffer = StringBuffer('[WARN] $message');
      if (error != null) {
        buffer.write(' | Error: $error');
      }
      if (stackTrace != null) {
        buffer.write('\n$stackTrace');
      }
      debugPrint(buffer.toString());
    }
  }

  /// Logs an error message with optional error and stack trace.
  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer('[ERROR] $message');
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    debugPrint(buffer.toString());
  }
}
