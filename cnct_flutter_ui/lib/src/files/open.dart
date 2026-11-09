import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'open_io.dart' if (dart.library.js_interop) 'open_web.dart' as platform;

/// Hand a received file to the platform: the share sheet on a phone — from which it opens in any
/// viewer, or saves — the default app on a desktop, and a download with its own name on the web.
///
/// [origin] is where the tap was, which an iPad needs to point its share popover at.
Future<void> openReceivedFile(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
  Rect? origin,
}) =>
    platform.openReceivedFile(bytes, filename: filename, mimeType: mimeType, origin: origin);

/// A name safe to write to disk: no directories, nothing a file system refuses.
String safeFilename(String name) {
  final base = name.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_');
  return base.isEmpty || base == '.' || base == '..' ? 'file' : base;
}
