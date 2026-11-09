import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;

import 'picked_file.dart';

/// Where picked files come from. The system's own pickers in an app; something scripted in a test.
abstract class FileSource {
  /// Whether this device has a camera worth offering — phones and tablets.
  bool get hasCamera;

  /// The photo library, several at once: pictures and videos.
  Future<List<PickedFile>> photos();

  /// One photo, taken now.
  Future<List<PickedFile>> camera();

  /// Anything else: PDFs, documents, spreadsheets, audio.
  Future<List<PickedFile>> files();
}

/// The system pickers, through the official flutter.dev plugins.
///
/// **No storage permission is asked for.** Android's photo picker and iOS's `PHPickerViewController`
/// hand over only what the visitor chose, and `requestFullMetadata: false` keeps iOS from asking to
/// read the whole library. The camera does need the app's `NSCameraUsageDescription` on iOS — see
/// the README.
class SystemFileSource implements FileSource {
  SystemFileSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  bool get hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<List<PickedFile>> photos() async =>
      _all(await _picker.pickMultipleMedia(requestFullMetadata: false));

  @override
  Future<List<PickedFile>> camera() async {
    final photo = await _picker.pickImage(source: ImageSource.camera, requestFullMetadata: false);
    return photo == null ? const [] : _all([photo]);
  }

  @override
  Future<List<PickedFile>> files() async => _all(await openFiles(acceptedTypeGroups: [_accepted]));

  Future<List<PickedFile>> _all(List<XFile> files) => Future.wait(files.map(PickedFile.fromXFile));

  /// What the platform takes, said in each picker's own vocabulary: MIME types for Android and the
  /// web, extensions for desktops, uniform type identifiers for Apple's. HEIC is offered too — it is
  /// converted to JPEG before it is sent.
  static final _accepted = XTypeGroup(
    label: 'CNCT',
    mimeTypes: [...CnctAttachmentRules.acceptedTypes, 'image/heic', 'image/heif'],
    extensions: const [
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'aac', 'mp3', 'ogg', 'm4a', 'amr', //
      'mp4', '3gp', 'mov', 'pdf', 'doc', 'docx', 'xlsx', 'txt', 'csv',
    ],
    uniformTypeIdentifiers: const [
      'public.jpeg', 'public.png', 'org.webmproject.webp', 'com.compuserve.gif', 'public.heic', //
      'public.heif', 'public.mp3', 'public.mpeg-4-audio', 'public.aac-audio',
      'org.3gpp.adaptive-multi-rate-audio', 'public.mpeg-4', 'public.3gpp',
      'com.apple.quicktime-movie', 'com.adobe.pdf', 'com.microsoft.word.doc',
      'org.openxmlformats.wordprocessingml.document', 'org.openxmlformats.spreadsheetml.sheet',
      'public.plain-text', 'public.comma-separated-values-text',
    ],
  );
}
