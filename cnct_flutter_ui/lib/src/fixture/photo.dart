import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A landscape photograph, drawn rather than shipped: an evening sky over the sea, with a headland.
/// Small, so the fixture costs nothing to build; a real picture, so the thumbnail and the viewer
/// are tested on a real decode rather than a grey box.
Uint8List fixturePhoto({int width = 480, int height = 320, int padTo = 0}) {
  final image = img.Image(width: width, height: height);
  final horizon = (height * 0.62).round();
  final sunX = width * 0.68;
  final sunY = height * 0.5;
  final sunRadius = height * 0.12;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      int r, g, b;
      if (y < horizon) {
        // Sky: deep blue at the top, warming to apricot at the horizon.
        final t = y / horizon;
        r = (40 + 215 * t).round();
        g = (70 + 120 * t).round();
        b = (140 - 30 * t).round();
        final d = math.sqrt(math.pow(x - sunX, 2) + math.pow(y - sunY, 2));
        if (d < sunRadius) {
          r = 255;
          g = 226;
          b = 160;
        } else if (d < sunRadius * 2.4) {
          final glow = 1 - (d - sunRadius) / (sunRadius * 1.4);
          r = (r + (255 - r) * glow * 0.5).round();
          g = (g + (210 - g) * glow * 0.5).round();
          b = (b + (150 - b) * glow * 0.3).round();
        }
      } else {
        // Sea: darker as it comes closer, with the sun's path on it.
        final t = (y - horizon) / (height - horizon);
        r = (30 + 40 * (1 - t)).round();
        g = (70 + 50 * (1 - t)).round();
        b = (110 + 40 * (1 - t)).round();
        final path = (x - sunX).abs() < (sunRadius * (1 + t * 2)) && (y % 6 < 2);
        if (path) {
          r = math.min(255, r + 120);
          g = math.min(255, g + 90);
          b = math.min(255, b + 40);
        }
      }
      // A headland on the left, in silhouette.
      final ridge = horizon - (math.max(0, (width * 0.38 - x)) * 0.5) + 6 * math.sin(x / 13);
      if (y > ridge && x < width * 0.42 && y < horizon + 4) {
        r = 34;
        g = 38;
        b = 52;
      }
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  final jpeg = img.encodeJpg(image, quality: 82);
  if (padTo <= jpeg.length) return jpeg;
  // Bytes after the end-of-image marker are ignored by every decoder: a picture of the size a
  // phone's photo would be, for a test that watches an upload go, without encoding one that big.
  return Uint8List(padTo)..setRange(0, jpeg.length, jpeg);
}

/// The smallest PDF that opens.
final Uint8List fixturePdf = Uint8List.fromList('%PDF-1.4\n'
        '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
        '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
        '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj\n'
        'trailer<</Root 1 0 R>>\n%%EOF\n'
    .codeUnits);
