import 'dart:typed_data';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:cross_file/cross_file.dart';

/// A file the visitor picked, before it is checked, converted or sent.
///
/// Read lazily: a 50 MB video is streamed to the server rather than held in memory, and only the
/// photos — which have to be decoded anyway, for a thumbnail and for HEIC — are read whole.
class PickedFile {
  PickedFile({
    required this.name,
    required this.mimeType,
    required this.length,
    required Future<Uint8List> Function() readBytes,
    required Stream<List<int>> Function() openRead,
  })  : _readBytes = readBytes,
        _openRead = openRead;

  /// A file already in memory.
  factory PickedFile.bytes(Uint8List bytes, {required String name, String? mimeType}) => PickedFile(
        name: name,
        mimeType: mimeType ?? CnctAttachmentRules.mimeTypeFor(name),
        length: bytes.length,
        readBytes: () async => bytes,
        openRead: () => Stream.value(bytes),
      );

  /// A file from a picker. Pickers often know a name and no type, so the type falls back to the
  /// one the name implies.
  static Future<PickedFile> fromXFile(XFile file) async {
    final declared = file.mimeType;
    final name = file.name.isEmpty ? 'file' : file.name;
    return PickedFile(
      name: name,
      mimeType: declared == null || declared.isEmpty || declared == 'application/octet-stream'
          ? CnctAttachmentRules.mimeTypeFor(name)
          : declared,
      length: await file.length(),
      readBytes: file.readAsBytes,
      openRead: () => file.openRead(),
    );
  }

  final String name;
  final String mimeType;
  final int length;
  final Future<Uint8List> Function() _readBytes;
  final Stream<List<int>> Function() _openRead;

  Future<Uint8List> readAsBytes() => _readBytes();
  Stream<List<int>> openRead() => _openRead();

  bool get isImage => mimeType.toLowerCase().startsWith('image/');
}

/// A file ready to go: converted where it had to be, and otherwise exactly as picked.
class PreparedFile {
  PreparedFile.bytes(Uint8List this.bytes, {required this.name, required this.mimeType})
      : length = bytes.length,
        _source = null;

  PreparedFile.untouched(PickedFile source)
      : name = source.name,
        mimeType = source.mimeType,
        length = source.length,
        bytes = null,
        _source = source;

  final String name;
  final String mimeType;
  final int length;

  /// The bytes, for a photo — which is also what its thumbnail is drawn from. Null for a file
  /// streamed from where it lies.
  final Uint8List? bytes;
  final PickedFile? _source;

  CnctUploadFile toUploadFile() {
    final data = bytes;
    if (data != null) return CnctUploadFile.bytes(data, filename: name, mimeType: mimeType);
    return CnctUploadFile.stream(_source!.openRead(),
        length: length, filename: name, mimeType: mimeType);
  }
}
