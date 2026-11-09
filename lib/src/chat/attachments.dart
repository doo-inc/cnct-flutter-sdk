import 'dart:async';

import '../exception.dart';
import 'chat_models.dart';

/// What the platform takes from a visitor, checked here so a UI can say so before uploading.
///
/// The server enforces every one of these itself — this is not the security boundary, it is the
/// difference between "that file is over 50 MB" said at once and the same sentence after a minute
/// of watching a progress bar on a phone's data.
abstract final class CnctAttachmentRules {
  /// Files on one message.
  static const maxFiles = 10;

  /// Bytes in one file: 50 MB.
  static const maxBytes = 50 * 1024 * 1024;

  /// Every type the platform accepts. Anything else is refused with 422.
  static const acceptedTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'audio/aac',
    'audio/mpeg',
    'audio/ogg',
    'audio/mp4',
    'audio/amr',
    'video/mp4',
    'video/3gpp',
    'video/quicktime',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv',
  };

  /// The MIME type for a file name, for a picker that hands over a name and no type — or the
  /// generic octet-stream, which [check] refuses. Covers what [acceptedTypes] holds, plus HEIC so
  /// that it can be recognised and converted rather than refused for being unknown.
  static String mimeTypeFor(String filename) {
    final dot = filename.lastIndexOf('.');
    final extension = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
    return _byExtension[extension] ?? 'application/octet-stream';
  }

  static const _byExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'aac': 'audio/aac',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'oga': 'audio/ogg',
    'm4a': 'audio/mp4',
    'amr': 'audio/amr',
    'mp4': 'video/mp4',
    '3gp': 'video/3gpp',
    'mov': 'video/quicktime',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'csv': 'text/csv',
  };

  /// Whether the platform takes this type. Parameters (`; charset=utf-8`) and case are ignored.
  static bool accepts(String mimeType) => acceptedTypes.contains(_bare(mimeType));

  /// True for an iPhone photo — or an Android one — in HEIC or HEIF.
  ///
  /// **The platform does not take these**, and phones take photos in them by default. Convert to
  /// JPEG before uploading; `cnct_flutter_ui` does. This package has no image codec, deliberately:
  /// it runs on a server too, and decoding HEIC needs the platform's own decoder.
  static bool isHeic(String mimeType, [String? filename]) {
    final type = _bare(mimeType);
    if (type == 'image/heic' || type == 'image/heif' || type.startsWith('image/heic-')) {
      return true;
    }
    final name = filename?.toLowerCase() ?? '';
    return name.endsWith('.heic') || name.endsWith('.heif');
  }

  /// Why a file cannot be sent, or null when it can. [alreadyAttached] is how many files the
  /// message already carries, so the eleventh is refused rather than the whole message.
  ///
  /// The codes are [CnctErrorCode.tooManyFiles], [CnctErrorCode.tooLarge] and
  /// [CnctErrorCode.unsupportedType]; the message is a sentence for a developer — a UI says it in
  /// its own words, in the visitor's language.
  static CnctException? check({
    required String filename,
    required String mimeType,
    required int bytes,
    int alreadyAttached = 0,
  }) {
    if (alreadyAttached >= maxFiles) {
      return CnctException('Up to $maxFiles files at a time.', code: CnctErrorCode.tooManyFiles);
    }
    if (bytes > maxBytes) {
      return CnctException('$filename is over 50 MB.', code: CnctErrorCode.tooLarge);
    }
    if (isHeic(mimeType, filename)) {
      return CnctException(
        '$filename is HEIC, which CNCT does not accept. Convert it to JPEG first.',
        code: CnctErrorCode.unsupportedType,
        details: const {'heic': true},
      );
    }
    if (!accepts(mimeType)) {
      return CnctException(
        '$filename is ${_bare(mimeType)}, which CNCT does not accept.',
        code: CnctErrorCode.unsupportedType,
      );
    }
    return null;
  }

  static String _bare(String mimeType) => mimeType.split(';').first.trim().toLowerCase();
}

/// A file on its way up: the bytes, or a stream of them, with a name and a type.
///
/// The name and type are required rather than guessed because a picker always knows them and a
/// guess made here would be wrong in exactly the cases that matter — a `.HEIC` the camera named,
/// a PDF saved without an extension.
class CnctUploadFile {
  /// A file already in memory. It is sent in 64 KB pieces so progress moves smoothly rather than
  /// jumping from nothing to done.
  CnctUploadFile.bytes(
    List<int> bytes, {
    required this.filename,
    required this.mimeType,
  })  : length = bytes.length,
        _bytes = bytes,
        _stream = null;

  /// A file read as it goes, so a 50 MB video never has to sit in memory whole. [length] is
  /// required: the request declares its size up front, and progress is measured against it.
  ///
  /// A stream can be read once, so an upload made from one cannot be retried — pick the file again.
  CnctUploadFile.stream(
    Stream<List<int>> stream, {
    required this.length,
    required this.filename,
    required this.mimeType,
  })  : _bytes = null,
        _stream = stream;

  final String filename;
  final String mimeType;

  /// Size in bytes.
  final int length;

  final List<int>? _bytes;
  final Stream<List<int>>? _stream;

  /// The bytes, when this file was made from them. Null for a stream.
  List<int>? get bytes => _bytes;

  static const _piece = 64 * 1024;

  /// The file's contents, in pieces.
  Stream<List<int>> openRead() {
    final bytes = _bytes;
    if (bytes == null) return _stream!;
    return Stream.fromIterable([
      for (var start = 0; start < bytes.length; start += _piece)
        bytes.sublist(start, start + _piece > bytes.length ? bytes.length : start + _piece),
    ]);
  }

  /// [CnctAttachmentRules.check], for this file.
  CnctException? check({int alreadyAttached = 0}) => CnctAttachmentRules.check(
        filename: filename,
        mimeType: mimeType,
        bytes: length,
        alreadyAttached: alreadyAttached,
      );
}

/// One file going up, as `CnctChatClient.upload` returns it.
///
/// A handle rather than a bare future because a picked file is something a person watches and can
/// take back: [progress] drives the ring on its chip, and [cancel] is the chip's remove button.
class CnctUpload {
  CnctUpload._(this.file);

  final CnctUploadFile file;

  final _result = Completer<CnctChatAttachment>();
  final _progress = StreamController<double>.broadcast();
  double _latest = 0;
  bool _cancelled = false;

  /// How much has gone, from 0 to 1. Measured as bytes are handed to the network, so it tracks the
  /// upload rather than the read.
  double get progress => _latest;

  /// Every change to [progress].
  Stream<double> get progressChanges => _progress.stream;

  /// The stored file, to send with `send(attachments: [...])`. Fails with the refusal — checked
  /// before anything is sent where possible, the server's otherwise — or with
  /// [CnctErrorCode.cancelled] after [cancel].
  Future<CnctChatAttachment> get result => _result.future;

  bool get isCancelled => _cancelled;
  bool get isDone => _result.isCompleted;

  /// Take it back. [result] fails at once; the request itself stops at its next piece.
  void cancel() {
    if (_result.isCompleted) return;
    _cancelled = true;
    _fail(CnctException('The upload was cancelled.', code: CnctErrorCode.cancelled));
  }

  void _report(double value) {
    if (_cancelled || _result.isCompleted) return;
    _latest = value.clamp(0, 1).toDouble();
    if (!_progress.isClosed) _progress.add(_latest);
  }

  void _complete(CnctChatAttachment attachment) {
    if (_result.isCompleted) return;
    _report(1);
    _result.complete(attachment);
    unawaited(_progress.close());
  }

  void _fail(CnctException error) {
    if (_result.isCompleted) return;
    _result.completeError(error);
    // Nobody may be listening yet; an unhandled error here would surface as a crash in a zone that
    // has nothing to do with the upload.
    _result.future.ignore();
    unawaited(_progress.close());
  }
}

/// The side of a [CnctUpload] only the client sees. Not exported: an app holding an upload can
/// watch it and cancel it, and nothing else.
final class DrivenUpload extends CnctUpload {
  DrivenUpload(super.file) : super._();

  void report(double value) => _report(value);
  void complete(CnctChatAttachment attachment) => _complete(attachment);
  void fail(CnctException error) => _fail(error);
}
