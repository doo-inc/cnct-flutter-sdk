import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cnct_flutter_ui/src/theme.dart' show debugSystemFontFallback;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fonts, so text renders as text rather than as the boxes Flutter tests draw by default.
///
/// The default theme uses the platform's system font, which in a test is Roboto by name and has
/// no glyphs behind it: Noto Sans is loaded under that name to stand in for it, and Noto Sans
/// Arabic as the system's Arabic fallback. The custom theme names its own: Noto Serif with Noto
/// Naskh Arabic. And the Material icons, from the test bundle.
Future<void> loadTestFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader
          .addFont(Future.value(ByteData.sublistView(File('test/fonts/$file').readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Roboto', ['NotoSans-Regular.ttf', 'NotoSans-Bold.ttf']);
  await family('Noto Sans Arabic', ['NotoSansArabic-Regular.ttf', 'NotoSansArabic-Bold.ttf']);
  await family('Noto Serif', ['NotoSerif-Regular.ttf', 'NotoSerif-Bold.ttf']);
  await family('Noto Naskh Arabic', ['NotoNaskhArabic-Regular.ttf', 'NotoNaskhArabic-Bold.ttf']);

  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<Object?>;
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(entry['family']! as String);
    for (final font in (entry['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
  debugSystemFontFallback = const ['Noto Sans Arabic'];
}

/// Pump frames, and give the engine real time between them to decode pictures — which a test's
/// fake clock alone never does.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  }
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pump(const Duration(milliseconds: 60));
}

/// The repaint boundary under [finder], as a PNG at the view's density.
Future<Uint8List> capturePng(WidgetTester tester, Finder finder) async {
  final boundary = finder.evaluate().single.renderObject! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}
