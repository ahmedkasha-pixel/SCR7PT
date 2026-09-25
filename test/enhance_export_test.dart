import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan/core/processing/document_processor.dart';
import 'package:docscan/core/processing/pdf_exporter.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/features/scan/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('auto enhance lifts the shadow and the export uses that image', () async {
    final raw = _shadowedPage();
    final jpeg = Uint8List.fromList(img.encodeJpg(raw, quality: 90));

    final direct = applyFilter(raw, PageFilter.autoEnhance);
    _expectEnhanced(raw, direct);

    final session = ScanSession();
    await session.addBytes(jpeg);
    expect(session.current!.filter, PageFilter.autoEnhance);
    await session.commitPending();
    final page = session.current!;
    final exported = renderJpeg(page.originalJpeg, page.corners, page.filter);
    final filtered = img.decodeImage(exported)!;
    final preview = img.decodeImage(page.previewJpeg)!;
    expect(_meanAbs(filtered, preview), lessThan(6));

    final untouched = img.decodeImage(
      renderJpeg(page.originalJpeg, page.corners, PageFilter.original),
    )!;
    expect(_meanAbs(filtered, untouched), greaterThan(8));

    final pdf = await PdfExporter().build([exported]);
    final embedded = img.decodeImage(_jpegFromPdf(pdf))!;
    expect(embedded.width, filtered.width);
    expect(embedded.height, filtered.height);
    expect(_meanAbs(embedded, filtered), lessThan(6));
    expect(_meanAbs(embedded, untouched), greaterThan(8));
  });

  test('black and white keeps shadowed paper white', () {
    final raw = _shadowedPage();
    final mono = applyFilter(raw, PageFilter.blackAndWhite);
    final paper = mono.getPixel(180, 900);
    final ink = mono.getPixel(90, 641);
    expect(paper.r, greaterThan(240));
    expect(ink.r, lessThan(10));

    var black = 0;
    var seen = 0;
    for (var y = 820; y < 980; y += 2) {
      for (var x = 40; x < 500; x += 2) {
        seen++;
        if (mono.getPixel(x, y).r < 128) black++;
      }
    }
    expect(black / seen, lessThan(0.25));
  });

  test('writes before and after comparisons', () {
    final raw = _shadowedPage();
    final auto = applyFilter(raw, PageFilter.autoEnhance);
    final mono = applyFilter(raw, PageFilter.blackAndWhite);
    final dir = Directory('build/fix');
    dir.createSync(recursive: true);
    File('${dir.path}/before-after-auto.png').writeAsBytesSync(
      img.encodePng(_sideBySide(raw, auto)),
    );
    File('${dir.path}/before-after-bw.png').writeAsBytesSync(
      img.encodePng(_sideBySide(raw, mono)),
    );
    expect(File('${dir.path}/before-after-auto.png').lengthSync(), greaterThan(1000));
  });
}

void _expectEnhanced(img.Image raw, img.Image enhanced) {
  final rawShadow = _luma(raw.getPixel(180, 900));
  final nextShadow = _luma(enhanced.getPixel(180, 900));
  expect(nextShadow, greaterThan(rawShadow + 50));
  expect(nextShadow, greaterThan(180));

  final paper = enhanced.getPixel(180, 900);
  final spread = [
    paper.r.toInt(),
    paper.g.toInt(),
    paper.b.toInt(),
  ].reduce(math.max) - [
    paper.r.toInt(),
    paper.g.toInt(),
    paper.b.toInt(),
  ].reduce(math.min);
  expect(spread, lessThan(40));

  final ink = _luma(enhanced.getPixel(90, 641));
  expect(ink, lessThan(nextShadow - 40));

  final mark = enhanced.getPixel(598, 148);
  expect(mark.b, greaterThan(mark.r + 30));
}

img.Image _shadowedPage() {
  const width = 720;
  const height = 1024;
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    final t = ((y - height * 0.40) / (height * 0.30)).clamp(0.0, 1.0);
    final shadow = t * t * (3 - 2 * t);
    final gain = 1 - 0.78 * shadow;
    final red = (214 * gain).round();
    final green = (196 * gain).round();
    final blue = (162 * gain).round();
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, red, green, blue);
    }
  }
  for (final y in [120, 168, 216, 640, 688, 736]) {
    img.fillRect(
      image,
      x1: 64,
      y1: y,
      x2: 500,
      y2: y + 3,
      color: img.ColorRgb8(26, 22, 20),
    );
    img.fillRect(
      image,
      x1: 64,
      y1: y + 14,
      x2: 340,
      y2: y + 16,
      color: img.ColorRgb8(26, 22, 20),
    );
  }
  img.drawString(
    image,
    'SCR7PT 1042',
    font: img.arial14,
    x: 64,
    y: 80,
    color: img.ColorRgb8(22, 18, 16),
  );
  img.drawString(
    image,
    'amount due',
    font: img.arial14,
    x: 64,
    y: 860,
    color: img.ColorRgb8(22, 18, 16),
  );
  img.fillRect(
    image,
    x1: 590,
    y1: 140,
    x2: 606,
    y2: 156,
    color: img.ColorRgb8(28, 72, 176),
  );
  return image;
}

img.Image _sideBySide(img.Image left, img.Image right) {
  const gap = 16;
  final output = img.Image(
    width: left.width + gap + right.width,
    height: math.max(left.height, right.height),
    numChannels: 3,
  );
  img.fill(output, color: img.ColorRgb8(15, 23, 42));
  img.compositeImage(output, left);
  img.compositeImage(output, right, dstX: left.width + gap);
  return output;
}

int _luma(img.Pixel pixel) =>
    (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();

double _meanAbs(img.Image a, img.Image b) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < a.height; y += 4) {
    for (var x = 0; x < a.width; x += 4) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      sum += (pa.r - pb.r).abs() + (pa.g - pb.g).abs() + (pa.b - pb.b).abs();
      count++;
    }
  }
  return sum / count;
}

Uint8List _jpegFromPdf(Uint8List pdf) {
  for (var i = 0; i < pdf.length - 3; i++) {
    if (pdf[i] != 0xFF || pdf[i + 1] != 0xD8 || pdf[i + 2] != 0xFF) continue;
    for (var j = i + 3; j < pdf.length - 1; j++) {
      if (pdf[j] == 0xFF && pdf[j + 1] == 0xD9) {
        return Uint8List.sublistView(pdf, i, j + 2);
      }
    }
  }
  throw StateError('PDF has no JPEG page.');
}
