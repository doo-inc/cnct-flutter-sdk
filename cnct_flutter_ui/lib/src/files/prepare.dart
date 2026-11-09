import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'picked_file.dart';

/// The longest side a photo is sent at. Never upscaled.
const maxPhotoSide = 2560;

/// JPEG quality for a photo that had to be re-encoded: ~0.85, as the spec asks.
const jpegQuality = 85;

/// A decoded picture, upright, as straight RGBA.
class DecodedImage {
  const DecodedImage(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

/// Decodes [bytes] to at most [maxSide] on the long side. Swappable so a test can stand in for a
/// HEIC decoder, which a test machine does not have.
typedef ImageDecoder = Future<DecodedImage> Function(Uint8List bytes, {required int maxSide});

/// **Get a photo ready to send**: HEIC and HEIF become JPEG, and a photo larger than 2560 px on its
/// long side is scaled down, at JPEG quality 85. Everything else goes exactly as picked.
///
/// CNCT does not accept HEIC, and iPhones — and some Android phones — take photos in it by default.
/// Decoding uses the platform's own decoder through Flutter's engine (which applies the EXIF
/// orientation, so a photo taken upright stays upright); the JPEG is encoded in Dart, off the UI
/// thread, because `dart:ui` can only encode PNG. Re-encoding also drops EXIF, so a photo's GPS
/// position does not travel with it.
///
/// Throws when a HEIC cannot be decoded on this platform — the caller says so in a sentence rather
/// than uploading something the server will refuse.
Future<PreparedFile> prepareForUpload(PickedFile file, {ImageDecoder? decode}) async {
  final decoder = decode ?? decodeWithEngine;
  final heic = CnctAttachmentRules.isHeic(file.mimeType, file.name);
  final jpeg = file.mimeType.toLowerCase() == 'image/jpeg';
  if (!heic && !jpeg) {
    // Other pictures are read whole too, but only to draw their thumbnail: they go as they are.
    if (!file.isImage) return PreparedFile.untouched(file);
    return PreparedFile.bytes(await file.readAsBytes(), name: file.name, mimeType: file.mimeType);
  }

  final bytes = await file.readAsBytes();
  if (jpeg) {
    final size = jpegSize(bytes);
    if (size != null && math.max(size.width, size.height) <= maxPhotoSide) {
      return PreparedFile.bytes(bytes, name: file.name, mimeType: 'image/jpeg');
    }
  }
  final decoded = await decoder(bytes, maxSide: maxPhotoSide);
  final encoded = await compute(_encodeJpeg, decoded);
  return PreparedFile.bytes(encoded, name: jpegName(file.name), mimeType: 'image/jpeg');
}

/// `IMG_0001.HEIC` → `IMG_0001.jpg`.
String jpegName(String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  return '$stem.jpg';
}

Uint8List _encodeJpeg(DecodedImage image) {
  final picture = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: image.rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(picture, quality: jpegQuality);
}

/// The engine's decoder: Skia's codecs for JPEG, PNG, WebP and GIF, and the platform's for HEIC
/// (Android 9+, and Apple platforms through image_picker's own conversion before it gets here).
Future<DecodedImage> decodeWithEngine(Uint8List bytes, {required int maxSide}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final scale = math.min(1.0, maxSide / math.max(descriptor.width, descriptor.height));
  final codec = await descriptor.instantiateCodec(
    targetWidth: math.max(1, (descriptor.width * scale).round()),
    targetHeight: math.max(1, (descriptor.height * scale).round()),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final decoded = DecodedImage(data!.buffer.asUint8List(), image.width, image.height);
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return decoded;
}

/// A JPEG's size from its frame header, without decoding it — so a photo that needs nothing done
/// to it costs nothing. Null for anything this cannot read, which then goes through the decoder.
({int width, int height})? jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var at = 2;
  while (at + 9 < bytes.length) {
    if (bytes[at] != 0xFF) return null;
    final marker = bytes[at + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      at += 2;
      continue;
    }
    final length = (bytes[at + 2] << 8) | bytes[at + 3];
    // Start-of-frame markers, every flavour except the three that are not frames (DHT, JPG, DAC).
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      final height = (bytes[at + 5] << 8) | bytes[at + 6];
      final width = (bytes[at + 7] << 8) | bytes[at + 8];
      return (width: width, height: height);
    }
    at += 2 + length;
  }
  return null;
}
