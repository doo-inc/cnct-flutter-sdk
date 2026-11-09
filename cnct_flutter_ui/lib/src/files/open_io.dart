import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'open.dart' show safeFilename;

Future<void> openReceivedFile(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
  Rect? origin,
}) async {
  // A folder per download, so two files with one name never overwrite each other, under the
  // temporary directory the system clears on its own.
  final root = await getTemporaryDirectory();
  final folder = await Directory(
    '${root.path}/cnct_chat/${DateTime.now().microsecondsSinceEpoch}',
  ).create(recursive: true);
  final file = File('${folder.path}/${safeFilename(filename)}');
  await file.writeAsBytes(bytes, flush: true);

  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: safeFilename(filename))],
      sharePositionOrigin: origin,
    ));
    return;
  }
  await launchUrl(Uri.file(file.path));
}
