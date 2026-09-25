import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan/core/processing/pdf_exporter.dart';
import 'package:docscan/core/processing/signature_extract.dart';
import 'package:docscan/core/processing/signature_stamp.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('paper becomes transparent and ink stays opaque, including a shadow', () {
    final clean = _paper(width: 220, height: 120, shadow: false);
    _stroke(clean, 70, 40, 90, 18);
    final cleanOut = extractSignatureImage(clean, cleanliness: 0.5);
    expect(_opaqueFraction(cleanOut), lessThan(0.55));
    expect(_maxAlpha(cleanOut), greaterThan(200));
    expect(cleanOut.getPixel(0, 0).a, lessThan(20));

    final shadow = _paper(width: 220, height: 140, shadow: true);
    _stroke(shadow, 80, 50, 70, 16);
    final shadowOut = extractSignatureImage(
      shadow,
      cleanliness: 0.5,
      ink: SignatureInk.black,
    );
    expect(_opaqueFraction(shadowOut), lessThan(0.55));
    expect(_maxAlpha(shadowOut), greaterThan(180));
    final ink = _darkestOpaque(shadowOut);
    expect(ink.r, lessThan(30));
    expect(ink.g, lessThan(30));
    expect(ink.b, lessThan(30));
  });

  test('a placed signature keeps its position and scale in the PDF page', () async {
    final page = img.Image(width: 400, height: 300, numChannels: 3);
    img.fill(page, color: img.ColorRgb8(250, 250, 248));
    final mark = img.Image(width: 80, height: 30, numChannels: 4);
    img.fill(mark, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      mark,
      x1: 0,
      y1: 0,
      x2: 79,
      y2: 29,
      color: img.ColorRgba8(10, 10, 12, 255),
    );
    final png = Uint8List.fromList(img.encodePng(mark));
    final stamped = stampImage(page, [
      StampPayload(
        png: png,
        centerX: 0.5,
        centerY: 0.5,
        width: 0.2,
        height: 0.1,
        rotation: 0,
      ),
    ]);
    expect(stamped.width, 400);
    expect(stamped.height, 300);
    final center = stamped.getPixel(200, 150);
    expect(center.r, lessThan(40));
    final outside = stamped.getPixel(8, 8);
    expect(outside.r, greaterThan(230));
    var dark = 0;
    for (var x = 0; x < stamped.width; x++) {
      if (stamped.getPixel(x, 150).r < 80) dark++;
    }
    expect(dark, inInclusiveRange(70, 100));

    final jpeg = Uint8List.fromList(img.encodeJpg(stamped, quality: 95));
    final pdf = await PdfExporter().build([jpeg]);
    final embedded = _jpegFromPdf(pdf);
    final decoded = img.decodeImage(embedded)!;
    expect(decoded.width, 400);
    expect(decoded.getPixel(200, 150).r, lessThan(50));
    expect(decoded.getPixel(8, 8).r, greaterThan(220));
    var embeddedDark = 0;
    for (var x = 0; x < decoded.width; x++) {
      if (decoded.getPixel(x, 150).r < 80) embeddedDark++;
    }
    expect(embeddedDark, inInclusiveRange(60, 110));
  });

  test('writes the signature background comparison', () {
    final clean = _paper(width: 360, height: 180, shadow: false);
    _stroke(clean, 90, 70, 180, 28);
    final shadow = _paper(width: 360, height: 180, shadow: true);
    _stroke(shadow, 100, 78, 160, 26);
    final lined = _paper(width: 360, height: 180, shadow: false, lines: true);
    _stroke(lined, 96, 74, 170, 30);

    final cases = [
      (clean, 0.45, SignatureInk.original),
      (shadow, 0.55, SignatureInk.black),
      (lined, 0.72, SignatureInk.blue),
    ];
    const cellW = 280;
    const cellH = 180;
    const gap = 10;
    final board = img.Image(
      width: gap + 3 * (cellW + gap),
      height: gap + cases.length * (cellH + gap),
      numChannels: 3,
    );
    img.fill(board, color: img.ColorRgb8(232, 236, 242));
    for (var row = 0; row < cases.length; row++) {
      final source = cases[row].$1;
      final extracted = extractSignatureImage(
        source,
        cleanliness: cases[row].$2,
        ink: cases[row].$3,
      );
      final top = gap + row * (cellH + gap);
      _blit(board, source, gap, top, cellW, cellH);
      _blit(board, _onChecker(extracted), gap + cellW + gap, top, cellW, cellH);
      final doc = img.Image(width: 320, height: 220, numChannels: 3);
      img.fill(doc, color: img.ColorRgb8(248, 246, 240));
      for (var line = 0; line < 6; line++) {
        img.fillRect(
          doc,
          x1: 28,
          y1: 36 + line * 26,
          x2: 250,
          y2: 42 + line * 26,
          color: img.ColorRgb8(190, 186, 176),
        );
      }
      final placed = stampImage(doc, [
        StampPayload(
          png: Uint8List.fromList(img.encodePng(extracted)),
          centerX: 0.62,
          centerY: 0.72,
          width: 0.5,
          height: 0.5 * (extracted.height / extracted.width) * (doc.width / doc.height),
          rotation: -0.08,
        ),
      ]);
      _blit(board, placed, gap + 2 * (cellW + gap), top, cellW, cellH);
    }
    final file = File('build/fix/signature-bg-removal.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(board));
    expect(file.lengthSync(), greaterThan(1000));
  });
}

img.Image _paper({
  required int width,
  required int height,
  required bool shadow,
  bool lines = false,
}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var luma = shadow ? (150 + (x / width) * 105).round() : 246;
      if (lines && y % 22 < 2) luma = 188;
      image.setPixelRgb(x, y, luma, luma - 2, luma - 6);
    }
  }
  return image;
}

void _stroke(img.Image image, int x, int y, int width, int height) {
  img.fillRect(
    image,
    x1: x,
    y1: y,
    x2: x + width,
    y2: y + height ~/ 3,
    color: img.ColorRgb8(16, 16, 18),
  );
  img.fillRect(
    image,
    x1: x + width ~/ 3,
    y1: y,
    x2: x + width ~/ 3 + 8,
    y2: y + height,
    color: img.ColorRgb8(16, 16, 18),
  );
}

double _opaqueFraction(img.Image image) {
  var opaque = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a > 40) opaque++;
    }
  }
  return opaque / (image.width * image.height);
}

int _maxAlpha(img.Image image) {
  var maxA = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final alpha = image.getPixel(x, y).a.toInt();
      if (alpha > maxA) maxA = alpha;
    }
  }
  return maxA;
}

img.Pixel _darkestOpaque(img.Image image) {
  img.Pixel? chosen;
  var best = 999;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      if (pixel.a < 180) continue;
      final luma = pixel.r + pixel.g + pixel.b;
      if (luma < best) {
        best = luma.toInt();
        chosen = pixel;
      }
    }
  }
  return chosen!;
}

img.Image _onChecker(img.Image signature) {
  final board = img.Image(
    width: math.max(signature.width, 40),
    height: math.max(signature.height, 40),
    numChannels: 3,
  );
  for (var y = 0; y < board.height; y++) {
    for (var x = 0; x < board.width; x++) {
      final alt = ((x ~/ 12) + (y ~/ 12)).isOdd;
      final shade = alt ? 176 : 232;
      board.setPixelRgb(x, y, shade, shade, shade);
    }
  }
  img.compositeImage(board, signature, dstX: 0, dstY: 0);
  return board;
}

void _blit(img.Image board, img.Image sprite, int left, int top, int boxW, int boxH) {
  img.fillRect(
    board,
    x1: left,
    y1: top,
    x2: left + boxW - 1,
    y2: top + boxH - 1,
    color: img.ColorRgb8(15, 23, 42),
  );
  final scale = math.min(boxW / sprite.width, boxH / sprite.height);
  final w = math.max(1, (sprite.width * scale).round());
  final h = math.max(1, (sprite.height * scale).round());
  final resized = img.copyResize(sprite, width: w, height: h);
  img.compositeImage(
    board,
    resized,
    dstX: left + (boxW - w) ~/ 2,
    dstY: top + (boxH - h) ~/ 2,
  );
}

Uint8List _jpegFromPdf(Uint8List pdf) {
  final start = _indexOf(pdf, [0xFF, 0xD8, 0xFF]);
  expect(start, greaterThanOrEqualTo(0));
  var end = -1;
  for (var i = pdf.length - 2; i > start; i--) {
    if (pdf[i] == 0xFF && pdf[i + 1] == 0xD9) {
      end = i + 2;
      break;
    }
  }
  expect(end, greaterThan(start));
  return Uint8List.sublistView(pdf, start, end);
}

int _indexOf(Uint8List data, List<int> needle) {
  for (var i = 0; i <= data.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
