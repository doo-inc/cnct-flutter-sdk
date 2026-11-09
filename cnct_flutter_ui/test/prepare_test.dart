import 'dart:typed_data';

import 'package:cnct_flutter_ui/fixture.dart';
import 'package:cnct_flutter_ui/src/files/picked_file.dart';
import 'package:cnct_flutter_ui/src/files/prepare.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Stands in for the platform's HEIC decoder, which a test machine does not have: whatever it is
/// given, it answers with a 3000 × 4000 picture, as an iPhone's portrait photo decodes.
Future<DecodedImage> fakeHeicDecoder(Uint8List bytes, {required int maxSide}) async {
  const width = 3000;
  const height = 4000;
  final scale = maxSide / height;
  final w = (width * scale).round();
  final h = (height * scale).round();
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba
      ..[i] = 200
      ..[i + 1] = 120
      ..[i + 2] = 40
      ..[i + 3] = 255;
  }
  return DecodedImage(rgba, w, h);
}

bool isJpeg(Uint8List bytes) => bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HEIC becomes JPEG, at most 2560 px on the long side, named .jpg', () async {
    final heic = PickedFile.bytes(Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]),
        name: 'IMG_0001.HEIC', mimeType: 'image/heic');

    final prepared = await prepareForUpload(heic, decode: fakeHeicDecoder);

    expect(prepared.name, 'IMG_0001.jpg');
    expect(prepared.mimeType, 'image/jpeg');
    expect(isJpeg(prepared.bytes!), isTrue);
    final size = jpegSize(prepared.bytes!)!;
    expect(size.height, 2560);
    expect(size.width, 1920);
    expect(prepared.toUploadFile().check(), isNull);
  });

  test('a HEIF named only by its extension is caught too', () async {
    final heif =
        PickedFile.bytes(Uint8List(8), name: 'photo.heif', mimeType: 'application/octet-stream');
    final prepared = await prepareForUpload(heif, decode: fakeHeicDecoder);
    expect(prepared.mimeType, 'image/jpeg');
  });

  test('a HEIC this platform cannot decode is an error, not an upload the server refuses',
      () async {
    final heic = PickedFile.bytes(Uint8List(8), name: 'IMG.heic', mimeType: 'image/heic');
    await expectLater(
      prepareForUpload(heic, decode: (_, {required maxSide}) async => throw Exception('no codec')),
      throwsException,
    );
  });

  testWidgets('a photo over 2560 px is scaled down, never up, with the engine’s own decoder',
      (tester) async {
    final big = img.encodeJpg(img.Image(width: 4032, height: 3024), quality: 80);
    final prepared = await tester.runAsync(
      () => prepareForUpload(PickedFile.bytes(big, name: 'IMG_0002.jpg', mimeType: 'image/jpeg')),
    );
    final size = jpegSize(prepared!.bytes!)!;
    expect(size.width, 2560);
    expect(size.height, 1920);
    expect(prepared.name, 'IMG_0002.jpg');
  });

  test('a photo within 2560 px goes exactly as it was', () async {
    final small = fixturePhoto(width: 480, height: 320);
    final prepared =
        await prepareForUpload(PickedFile.bytes(small, name: 'beach.jpg', mimeType: 'image/jpeg'));
    expect(identical(prepared.bytes, small) || listEquals(prepared.bytes, small), isTrue);
  });

  test('anything that is not a photo is left untouched, and streamed', () async {
    var read = 0;
    final pdf = PickedFile(
      name: 'invoice.pdf',
      mimeType: 'application/pdf',
      length: fixturePdf.length,
      readBytes: () async {
        read += 1;
        return fixturePdf;
      },
      openRead: () => Stream.value(fixturePdf),
    );
    final prepared = await prepareForUpload(pdf);
    expect(prepared.bytes, isNull);
    expect(read, 0);
    expect(prepared.toUploadFile().length, fixturePdf.length);
  });

  test('a PNG keeps its type: only photos are re-encoded', () async {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 3000, height: 3000)));
    final prepared = await prepareForUpload(PickedFile.bytes(png, name: 'shot.png'));
    expect(prepared.mimeType, 'image/png');
    expect(prepared.bytes, png);
  });

  test('a JPEG’s size is read from its header without decoding it', () {
    expect(jpegSize(fixturePhoto(width: 300, height: 200)), (width: 300, height: 200));
    expect(jpegSize(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
