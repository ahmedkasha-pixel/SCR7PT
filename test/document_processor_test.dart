import 'dart:math' as math;

import 'package:docscan/core/app_config.dart';
import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/document_processor.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('detects a bright page on a dark background', () {
    final image = img.Image(width: 200, height: 180, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(12, 14, 16));
    img.fillRect(
      image,
      x1: 36,
      y1: 28,
      x2: 164,
      y2: 150,
      color: img.ColorRgb8(246, 244, 238),
    );
    final quad = detectQuad(image);
    expect(quad.topLeft.x * 199, closeTo(36, 14));
    expect(quad.topLeft.y * 179, closeTo(28, 14));
    expect(quad.bottomRight.x * 199, closeTo(164, 14));
    expect(quad.bottomRight.y * 179, closeTo(150, 14));
  });

  test('a flat image falls back to the standard inset', () {
    final image = img.Image(width: 80, height: 60, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(40, 40, 40));
    final quad = detectQuad(image);
    expect(quad.topLeft.x, closeTo(Quad.standard.topLeft.x, 0.001));
    expect(quad.bottomRight.x, closeTo(Quad.standard.bottomRight.x, 0.001));
  });

  test('full-frame render keeps the source pixel', () {
    final image = img.Image(width: 24, height: 24, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(0, 0, 180));
    image.setPixelRgb(12, 12, 230, 20, 20);
    final rendered = renderImage(image, Quad.fullFrame, PageFilter.original);
    final pixel = rendered.getPixel(12, 12);
    expect(pixel.r, greaterThan(200));
    expect(pixel.b, lessThan(40));
  });

  test('perspective crop keeps the selected half', () {
    final image = img.Image(width: 80, height: 40, numChannels: 3);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 39,
      y2: 39,
      color: img.ColorRgb8(20, 160, 20),
    );
    img.fillRect(
      image,
      x1: 40,
      y1: 0,
      x2: 79,
      y2: 39,
      color: img.ColorRgb8(20, 20, 200),
    );
    const rightHalf = Quad(
      topLeft: NormPoint(0.5, 0),
      topRight: NormPoint(1, 0),
      bottomRight: NormPoint(1, 1),
      bottomLeft: NormPoint(0.5, 1),
    );
    final rendered = renderImage(image, rightHalf, PageFilter.original);
    final center = rendered.getPixel(rendered.width ~/ 2, rendered.height ~/ 2);
    expect(center.b, greaterThan(center.r));
    expect(center.b, greaterThan(center.g));
  });

  test('filters change luminance as named', () {
    final image = img.Image(width: 30, height: 16, numChannels: 3);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 14,
      y2: 15,
      color: img.ColorRgb8(30, 30, 30),
    );
    img.fillRect(
      image,
      x1: 15,
      y1: 0,
      x2: 29,
      y2: 15,
      color: img.ColorRgb8(220, 40, 40),
    );

    final gray = applyFilter(image, PageFilter.grayscale);
    final grayPixel = gray.getPixel(20, 8);
    expect(grayPixel.r, grayPixel.g);
    expect(grayPixel.g, grayPixel.b);

    final mono = applyFilter(image, PageFilter.blackAndWhite);
    final dark = mono.getPixel(4, 8).r;
    final light = mono.getPixel(22, 8).r;
    expect(dark == 0 || dark == 255, isTrue);
    expect(light, greaterThan(240));

    final bright = applyFilter(image, PageFilter.brighten);
    expect(bright.getPixel(4, 8).r, greaterThan(30));
  });

  test('preparePage returns a jpeg and detected corners', () {
    final image = img.Image(width: 120, height: 90, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(8, 8, 8));
    img.fillRect(
      image,
      x1: 20,
      y1: 15,
      x2: 100,
      y2: 75,
      color: img.ColorRgb8(250, 250, 250),
    );
    final prepared = preparePage(img.encodeJpg(image));
    expect(prepared.originalJpeg.first, 0xFF);
    expect(prepared.originalJpeg[1], 0xD8);
    expect(prepared.corners, hasLength(8));
    expect(prepared.width, 120);
  });

  test('a tall capture is not reduced below a 2000 px long side', () {
    final image = img.Image(width: 480, height: 2200, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(232, 220, 200));
    final prepared = preparePage(img.encodeJpg(image, quality: 75));
    expect(prepared.width, 480);
    expect(prepared.height, 2200);
    expect(
      math.max(prepared.width, prepared.height),
      greaterThanOrEqualTo(2000),
    );
  });

  test('a 12 MP portrait A4 page stays near the sensor resolution', () {
    final size = a4ExportSizeFrom12Mp();
    expect(size.width, inInclusiveRange(2700, 3000));
    expect(size.height, inInclusiveRange(3900, 4096));
    expect(
      math.max(size.width, size.height),
      greaterThanOrEqualTo(2000),
    );
    expect(
      math.max(size.width, size.height),
      lessThanOrEqualTo(AppConfig.maxImageEdge),
    );
  });
}
