import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:cross_file/cross_file.dart';

import 'open.dart' show safeFilename;

/// On the web a received file is a download with its original name — there is no share sheet to
/// hand it to, and opening it in a tab would leave the chat.
Future<void> openReceivedFile(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
  Rect? origin,
}) =>
    XFile.fromData(bytes, name: safeFilename(filename), mimeType: mimeType)
        .saveTo(safeFilename(filename));
