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
  test(
    'auto enhance lifts the shadow and the export uses that image',
    () async {
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
    },
  );

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
    File('${dir.path}/before-after-auto.png')
        .writeAsBytesSync(img.encodePng(_sideBySide(raw, auto)));
    File('${dir.path}/before-after-bw.png')
        .writeAsBytesSync(img.encodePng(_sideBySide(raw, mono)));
    expect(
      File('${dir.path}/before-after-auto.png').lengthSync(),
      greaterThan(1000),
    );
  });

  test('auto enhance flattens paper and keeps shadow text crisp', () {
    final cases = [_hardShadow(), _diagonalShadow(), _handShadow()];
    final cells = <img.Image>[];
    for (final sample in cases) {
      final auto = applyFilter(sample.image, PageFilter.autoEnhance);
      final mono = applyFilter(sample.image, PageFilter.blackAndWhite);
      cells.add(sample.image);
      cells.add(auto);
      cells.add(mono);

      final std = _stddev(auto, sample.paper);
      expect(std, lessThan(6), reason: '${sample.name} paper stddev');
      expect(
        _meanAt(auto, sample.paper),
        greaterThan(248),
        reason: sample.name,
      );

      final litPaper = _meanAt(auto, sample.litPaper);
      final shadowPaper = _meanAt(auto, sample.shadowPaper);
      final litText = _meanAt(auto, sample.litText);
      final shadowText = _meanAt(auto, sample.shadowText);
      final litContrast = litPaper - litText;
      final shadowContrast = shadowPaper - shadowText;
      expect(litText, lessThan(55), reason: '${sample.name} lit text');
      expect(shadowText, lessThan(55), reason: '${sample.name} shadow text');
      expect(
        shadowContrast,
        greaterThan(litContrast * 0.75),
        reason: '${sample.name} contrast $shadowContrast vs $litContrast',
      );
    }

    final sheet = _montage(cells);
    final dir = Directory('build/fix');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/auto-cases.png');
    file.writeAsBytesSync(img.encodePng(sheet));
    expect(file.lengthSync(), greaterThan(1000));
    expect(file.lengthSync(), lessThan(4000000));
  });
}

void _expectEnhanced(img.Image raw, img.Image enhanced) {
  final rawShadow = _luma(raw.getPixel(180, 900));
  final nextShadow = _luma(enhanced.getPixel(180, 900));
  expect(nextShadow, greaterThan(rawShadow + 50));
  expect(nextShadow, greaterThan(180));

  final paper = enhanced.getPixel(180, 900);
  final spread =
      [paper.r.toInt(), paper.g.toInt(), paper.b.toInt()].reduce(math.max) -
      [paper.r.toInt(), paper.g.toInt(), paper.b.toInt()].reduce(math.min);
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

class _ShadowCase {
  _ShadowCase({
    required this.name,
    required this.image,
    required this.paper,
    required this.litPaper,
    required this.shadowPaper,
    required this.litText,
    required this.shadowText,
  });

  final String name;
  final img.Image image;
  final List<math.Point<int>> paper;
  final List<math.Point<int>> litPaper;
  final List<math.Point<int>> shadowPaper;
  final List<math.Point<int>> litText;
  final List<math.Point<int>> shadowText;
}

_ShadowCase _hardShadow() {
  return _paintPage(
    name: 'a',
    gainFor: (x, y, w, h) {
      final t = ((y - h * 0.48) / (h * 0.34)).clamp(0.0, 1.0);
      final shadow = t * t * (3 - 2 * t);
      return 1 - 0.8 * shadow;
    },
    litTextY: 64,
    shadowTextY: 392,
  );
}

_ShadowCase _diagonalShadow() {
  return _paintPage(
    name: 'b',
    gainFor: (x, y, w, h) {
      final u = (0.25 * x / (w - 1) + 0.9 * y / (h - 1)).clamp(0.0, 1.0);
      final shadow = u * u * (3 - 2 * u);
      return 1 - 0.78 * shadow;
    },
    litTextY: 48,
    shadowTextY: 470,
  );
}

_ShadowCase _handShadow() {
  final sample = _paintPage(
    name: 'c',
    gainFor: (x, y, w, h) {
      final cx = w * 0.5;
      final cy = h * 0.56;
      var distance = _ellipse(x, y, cx, cy + 8, 86, 62);
      for (var finger = 0; finger < 4; finger++) {
        final fx = cx - 42 + finger * 28;
        distance = math.min(
          distance,
          _capsule(x, y, fx, cy - 8, fx - 6, cy - 132, 15),
        );
      }
      distance = math.min(
        distance,
        _capsule(x, y, cx - 62, cy + 16, cx - 118, cy - 36, 16),
      );
      const edge = 46.0;
      final shadow = distance <= 0
          ? 1.0
          : 1 - ((distance / edge).clamp(0.0, 1.0));
      final soft = shadow * shadow * (3 - 2 * shadow);
      return 1 - 0.76 * soft;
    },
    litTextY: 36,
    shadowTextY: 318,
  );
  final inside = <math.Point<int>>[
    for (var x = 150; x <= 250; x += 14) math.Point(x, 360),
    for (var y = 250; y <= 300; y += 12) math.Point(210, y),
    math.Point(230, 400),
    math.Point(160, 330),
  ];
  sample.shadowPaper
    ..clear()
    ..addAll(inside);
  sample.paper.addAll(inside);
  return sample;
}

_ShadowCase _paintPage({
  required String name,
  required double Function(double x, double y, int w, int h) gainFor,
  required int litTextY,
  required int shadowTextY,
}) {
  const width = 400;
  const height = 560;
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final gain = gainFor(x.toDouble(), y.toDouble(), width, height);
      image.setPixelRgb(
        x,
        y,
        (214 * gain).round(),
        (196 * gain).round(),
        (162 * gain).round(),
      );
    }
  }
  const textX0 = 70;
  const textX1 = 300;
  for (final y in [litTextY, shadowTextY]) {
    img.fillRect(
      image,
      x1: textX0,
      y1: y,
      x2: textX1,
      y2: y + 3,
      color: img.ColorRgb8(24, 20, 18),
    );
  }
  final litText = [
    for (var x = 90; x < 240; x += 18) math.Point(x, litTextY + 1),
  ];
  final shadowText = [
    for (var x = 90; x < 240; x += 18) math.Point(x, shadowTextY + 1),
  ];
  bool clear(int x, int y) {
    if ((y - litTextY).abs() < 10 || (y - shadowTextY).abs() < 10) {
      if (x >= textX0 - 4 && x <= textX1 + 4) return false;
    }
    return true;
  }

  final paper = <math.Point<int>>[];
  for (var y = 12; y < height - 8; y += 10) {
    for (final x in [18, 340]) {
      if (clear(x, y)) paper.add(math.Point(x, y));
    }
  }
  final litPaper = paper.where((p) => (p.y - litTextY).abs() < 36).toList();
  final shadowPaper = paper
      .where((p) => (p.y - shadowTextY).abs() < 36)
      .toList();
  return _ShadowCase(
    name: name,
    image: image,
    paper: paper,
    litPaper: litPaper.isEmpty ? [math.Point(18, litTextY + 20)] : litPaper,
    shadowPaper: shadowPaper.isEmpty
        ? [math.Point(18, shadowTextY + 20)]
        : shadowPaper,
    litText: litText,
    shadowText: shadowText,
  );
}

double _ellipse(
  double x,
  double y,
  double cx,
  double cy,
  double rx,
  double ry,
) {
  final nx = (x - cx) / rx;
  final ny = (y - cy) / ry;
  return (math.sqrt(nx * nx + ny * ny) - 1) * math.min(rx, ry);
}

double _capsule(
  double x,
  double y,
  double x0,
  double y0,
  double x1,
  double y1,
  double radius,
) {
  final dx = x1 - x0;
  final dy = y1 - y0;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0
      ? 0.0
      : (((x - x0) * dx + (y - y0) * dy) / len2).clamp(0.0, 1.0);
  final px = x0 + t * dx;
  final py = y0 + t * dy;
  return math.sqrt((x - px) * (x - px) + (y - py) * (y - py)) - radius;
}

double _meanAt(img.Image image, List<math.Point<int>> points) {
  var sum = 0.0;
  for (final point in points) {
    sum += _luma(image.getPixel(point.x, point.y));
  }
  return sum / points.length;
}

double _stddev(img.Image image, List<math.Point<int>> points) {
  final mean = _meanAt(image, points);
  var sum = 0.0;
  for (final point in points) {
    final delta = _luma(image.getPixel(point.x, point.y)) - mean;
    sum += delta * delta;
  }
  return math.sqrt(sum / points.length);
}

img.Image _montage(List<img.Image> cells) {
  const columns = 3;
  const gap = 10;
  const header = 26;
  final cellW = cells.first.width;
  final cellH = cells.first.height;
  final rows = cells.length ~/ columns;
  final sheet = img.Image(
    width: columns * cellW + (columns + 1) * gap,
    height: rows * (cellH + header) + (rows + 1) * gap,
    numChannels: 3,
  );
  img.fill(sheet, color: img.ColorRgb8(15, 23, 42));
  const titles = [
    'a  input',
    'a  Auto enhance',
    'a  B&W',
    'b  input',
    'b  Auto enhance',
    'b  B&W',
    'c  input',
    'c  Auto enhance',
    'c  B&W',
  ];
  for (var i = 0; i < cells.length; i++) {
    final col = i % columns;
    final row = i ~/ columns;
    final x = gap + col * (cellW + gap);
    final y = gap + row * (cellH + header + gap);
    img.drawString(
      sheet,
      titles[i],
      font: img.arial14,
      x: x,
      y: y + 4,
      color: img.ColorRgb8(232, 233, 234),
    );
    img.compositeImage(sheet, cells[i], dstX: x, dstY: y + header);
  }
  return sheet;
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
