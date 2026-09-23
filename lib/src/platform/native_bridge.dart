import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Communicates with native Android (Kotlin) and iOS (Swift) platform channels
/// to perform file and directory operations with zero external dependencies.
class NativeBridge {
  const NativeBridge._();

  static const MethodChannel _channel = MethodChannel('flutter_eml_msg_viewer');

  /// Returns the path to the app's cache or temporary directory.
  ///
  /// Calls native Android `context.cacheDir` or iOS `cachesDirectory` / `NSTemporaryDirectory()`.
  /// In non-platform test environments where the method channel is unimplemented,
  /// falls back to [Directory.systemTemp.path].
  static Future<String> getTemporaryDirectory() async {
    try {
      final path = await _channel.invokeMethod<String>('getTempDirectory');
      if (path != null && path.isNotEmpty) {
        return path;
      }
    } on MissingPluginException {
      // In host-side flutter_test unit tests without mock channels
    } catch (_) {}

    return Directory.systemTemp.path;
  }

  /// Opens the file at [filePath] using the native OS viewer
  /// (Android: Intent.ACTION_VIEW with FileProvider; iOS: UIDocumentInteractionController).
  ///
  /// Returns `null` on success, or a human-readable reason on failure.
  static Future<String?> openFile(String filePath, {String? mimeType}) async {
    try {
      final success = await _channel.invokeMethod<bool>('openFile', {
        'path': filePath,
        'mimeType': mimeType,
      });
      return success == true ? null : 'no app available to open this file';
    } on PlatformException catch (e) {
      debugPrint('flutter_eml_msg_viewer: openFile failed: ${e.code} ${e.message}');
      return e.message ?? e.code;
    } on MissingPluginException {
      return 'native plugin not registered (do a full rebuild, not a hot restart)';
    } catch (e) {
      debugPrint('flutter_eml_msg_viewer: openFile failed: $e');
      return e.toString();
    }
  }
}
