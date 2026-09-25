import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

const handwritingFamily = 'Caveat';

bool _loaded = false;

/// Loads the Caveat handwriting face used by the signature fixtures.
Future<void> loadHandwritingFont() async {
  if (_loaded) return;
  final loader = FontLoader(handwritingFamily);
  final bytes = await File('test/fonts/Caveat.ttf').readAsBytes();
  loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
  _loaded = true;
}

/// A cursive ballpoint signature on a paper photo: grain, optional shadow,
/// optional ruling, a little blur, then JPEG noise.
Future<img.Image> renderBallpointOnPaper({
  required bool shadow,
  required bool lines,
  int width = 760,
  int height = 420,
}) async {
  await loadHandwritingFont();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFF3F0E8),
  );
  if (lines) {
    final rule = ui.Paint()
      ..color = const ui.Color(0xFFB7C3D6)
      ..strokeWidth = 1.4;
    for (var y = 34.0; y < height - 12; y += 26) {
      canvas.drawLine(
        ui.Offset(16, y),
        ui.Offset(width - 16, y),
        rule,
      );
    }
  }
  if (shadow) {
    final shade = ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        ui.Offset(width * 0.72, height * 0.15),
        const [ui.Color(0xCC2C2824), ui.Color(0x002C2824)],
      );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      shade,
    );
  }

  final paragraph = _signatureParagraph(width - 64);
  canvas.save();
  canvas.translate(36, height * 0.22);
  canvas.rotate(-0.05);
  canvas.drawParagraph(paragraph, ui.Offset.zero);
  canvas.restore();

  final picture = recorder.endRecording();
  final raster = await picture.toImage(width, height);
  final raw = await raster.toByteData(format: ui.ImageByteFormat.rawRgba);
  raster.dispose();
  picture.dispose();
  if (raw == null) {
    throw StateError('Could not rasterize the signature.');
  }
  var image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: raw.buffer,
    numChannels: 4,
  ).convert(format: img.Format.uint8, numChannels: 3);

  final random = math.Random(shadow ? 11 : (lines ? 17 : 3));
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final grain = random.nextInt(11) - 5;
      image.setPixelRgb(
        x,
        y,
        (pixel.r + grain).round().clamp(0, 255),
        (pixel.g + grain).round().clamp(0, 255),
        (pixel.b + grain - 1).round().clamp(0, 255),
      );
    }
  }
  image = img.gaussianBlur(image, radius: 1);
  return img.decodeJpg(img.encodeJpg(image, quality: 62))!;
}

/// Transparent PNG of the same handwriting, for placing on a page.
Future<Uint8List> renderSignatureMarkPng() async {
  await loadHandwritingFont();
  const width = 640;
  const height = 220;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paragraph = _signatureParagraph(width - 24);
  canvas.translate(8, 16);
  canvas.rotate(-0.04);
  canvas.drawParagraph(paragraph, ui.Offset.zero);
  final picture = recorder.endRecording();
  final raster = await picture.toImage(width, height);
  final png = await raster.toByteData(format: ui.ImageByteFormat.png);
  raster.dispose();
  picture.dispose();
  return png!.buffer.asUint8List();
}

ui.Paragraph _signatureParagraph(double width) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      fontFamily: handwritingFamily,
      fontSize: 108,
      height: 0.9,
    ),
  )
    ..pushStyle(
      ui.TextStyle(
        fontFamily: handwritingFamily,
        fontSize: 108,
        fontWeight: ui.FontWeight.w600,
        color: const ui.Color(0xFF1A3A8C),
      ),
    )
    ..addText('Jonathan Hale');
  return builder.build()..layout(ui.ParagraphConstraints(width: width));
}
