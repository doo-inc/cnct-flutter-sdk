// Renders the fixture conversation — the one every CNCT SDK renders — to PNGs, for a person to look
// at before a release: English and Arabic, light and dark with the default theme, and both
// languages with a custom one. CI uploads build/screenshots as the `screenshots` artifact.
//
// These are not golden tests. Nothing is compared, because what they exist to prove — that the
// Arabic is shaped and mirrored, that a mixed line reads in the right order, that dark mode is
// legible — is a judgement a person makes looking at them.
import 'dart:io';
import 'dart:typed_data';

import 'package:cnct_flutter_ui/cnct_flutter_ui.dart';
import 'package:cnct_flutter_ui/fixture.dart';
import 'package:cnct_flutter_ui/src/controller.dart' show UploadStatus;
import 'package:cnct_flutter_ui/src/files/picked_file.dart';
import 'package:cnct_flutter_ui/src/widgets/composer.dart';
import 'package:cnct_flutter_ui/src/widgets/scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/screens.dart';

/// A phone, in logical pixels, drawn at twice the density.
const width = 390.0;
const height = 1040.0;
const density = 2.0;

/// The custom theme of the spec: a red, small corners, a font of its own and a logo.
CnctChatTheme customTheme(Uint8List logo) => CnctChatTheme(
      primary: const Color(0xFFD7262E),
      cornerRadius: 8,
      font: 'Noto Serif',
      fontFallback: const ['Noto Naskh Arabic'],
      logo: MemoryImage(logo),
      appearance: CnctChatAppearance.light,
    );

/// A logo for the custom theme: a white wave over a red disc. Drawn here so no brand's mark is in
/// the repository.
Uint8List customLogo() {
  final image = img.Image(width: 160, height: 160, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillCircle(image, x: 80, y: 80, radius: 79, color: img.ColorRgba8(0xD7, 0x26, 0x2E, 255));
  for (var x = 26; x < 134; x++) {
    final y = 92 + (12 * ((x / 18) % 2 < 1 ? 1 : -1) * (((x % 18) - 9).abs() / 9 - 0.5)).round();
    img.fillCircle(image, x: x, y: y, radius: 6, color: img.ColorRgba8(255, 255, 255, 255));
  }
  img.fillCircle(image, x: 80, y: 56, radius: 14, color: img.ColorRgba8(255, 255, 255, 255));
  return img.encodePng(image);
}

void main() {
  setUpAll(loadTestFonts);

  final out = Directory('build/screenshots')..createSync(recursive: true);
  final logo = customLogo();

  for (final language in ['en', 'ar']) {
    for (final variant in ['light', 'dark', 'custom']) {
      testWidgets('chat-$language-$variant', (tester) async {
        tester.view.physicalSize = const Size(width * density, height * density);
        tester.view.devicePixelRatio = density;
        tester.platformDispatcher.platformBrightnessTestValue =
            variant == 'dark' ? Brightness.dark : Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final fixture = CnctChatFixture(language: language, stalledUploads: const {
          'beach.jpg': 0.4,
        });
        addTearDown(fixture.dispose);
        await tester.runAsync(fixture.prepare);

        const shot = Key('shot');
        await tester.pumpWidget(RepaintBoundary(
          key: shot,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            // A host theme the chat must not take anything from.
            theme: ThemeData(colorSchemeSeed: Colors.lime, fontFamily: 'Courier'),
            home: Scaffold(
              body: CnctChat(
                client: fixture.client,
                language: language == 'ar' ? CnctChatLanguage.ar : CnctChatLanguage.en,
                theme: variant == 'custom' ? customTheme(logo) : null,
                onClose: () {},
              ),
            ),
          ),
        ));
        await settle(tester);

        // Two files picked for the next message: a photo on its way up, and a PDF that is there.
        final composer = tester.element(find.byType(Composer));
        ChatScope.of(composer).controller.addFiles([
          PickedFile.bytes(fixturePhoto(width: 240, height: 160, padTo: 1677722),
              name: 'beach.jpg'),
          PickedFile.bytes(fixturePdf, name: 'menu.pdf'),
        ]);
        await settle(tester, rounds: 10);

        // What the tray must show: the photo part-way up, the PDF there.
        final chips = ChatScope.of(composer).controller.uploads;
        expect(chips.map((chip) => chip.name), ['beach.jpg', 'menu.pdf']);
        expect(chips.first.status, UploadStatus.uploading);
        expect(chips.first.progress.value, inInclusiveRange(0.38, 0.5));
        expect(chips.last.status, UploadStatus.done);

        final png = await capturePng(tester, find.byKey(shot));
        File('${out.path}/chat-$language-$variant.png').writeAsBytesSync(png);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
