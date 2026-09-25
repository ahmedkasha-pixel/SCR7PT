import 'dart:io';
import 'dart:math' as math;

import 'package:docscan/core/geometry/page_aspect.dart';
import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/document_processor.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a steep A4 page keeps the A4 ratio', () {
    final scene = _project(
      pageW: 210,
      pageH: 297,
      imageW: 640,
      imageH: 800,
      f: 900,
      distance: 520,
      yaw: 0.42,
      pitch: 0.62,
      roll: 0.08,
    );
    expect(scene.inside, isTrue, reason: 'corners left the frame');
    final geometry = recoverPageGeometry(
      quad: scene.quad,
      imageWidth: scene.image.width,
      imageHeight: scene.image.height,
    );
    expect(geometry.fromVanishingPoints, isTrue);
    expect(
      (geometry.longOverShort - a4Ratio).abs() / a4Ratio,
      lessThan(0.03),
    );
    expect(geometry.portrait, isTrue);

    final export = pagePixelSize(
      quad: scene.quad,
      imageWidth: 3000,
      imageHeight: 4000,
    );
    final ratio = export.height / export.width;
    expect((ratio - a4Ratio).abs() / a4Ratio, lessThan(0.01));
    expect(export.width, a4ShortPx);
    expect(export.height, a4LongPx);

    final warped = warpPerspective(scene.image, scene.quad);
    final warpedRatio = warped.height / warped.width;
    expect((warpedRatio - a4Ratio).abs() / a4Ratio, lessThan(0.01));
  });

  test('a long receipt is not snapped to A4 or Letter', () {
    final scene = _project(
      pageW: 80,
      pageH: 240,
      imageW: 480,
      imageH: 720,
      f: 700,
      distance: 420,
      yaw: -0.35,
      pitch: 0.4,
      roll: 0.02,
    );
    expect(scene.inside, isTrue, reason: 'receipt left the frame');
    final size = pagePixelSize(
      quad: scene.quad,
      imageWidth: scene.image.width,
      imageHeight: scene.image.height,
      mode: PageSizeMode.auto,
    );
    final ratio = math.max(size.width, size.height) /
        math.min(size.width, size.height);
    expect((ratio - 3).abs() / 3, lessThan(0.08));
    expect((ratio - a4Ratio).abs() / a4Ratio, greaterThan(paperSnapTolerance));
    expect(
      (ratio - letterRatio).abs() / letterRatio,
      greaterThan(paperSnapTolerance),
    );
    final original = pagePixelSize(
      quad: scene.quad,
      imageWidth: scene.image.width,
      imageHeight: scene.image.height,
      mode: PageSizeMode.original,
    );
    final originalRatio = math.max(original.width, original.height) /
        math.min(original.width, original.height);
    expect((originalRatio - ratio).abs(), lessThan(0.05));
  });

  test('pages in one document share the first page pixel size', () {
    final a4 = _project(
      pageW: 210,
      pageH: 297,
      imageW: 500,
      imageH: 640,
      f: 780,
      distance: 500,
      yaw: 0.2,
      pitch: 0.35,
      roll: 0.04,
    );
    final receipt = _project(
      pageW: 70,
      pageH: 210,
      imageW: 500,
      imageH: 640,
      f: 780,
      distance: 460,
      yaw: -0.25,
      pitch: 0.2,
      roll: 0,
    );
    expect(a4.inside && receipt.inside, isTrue);
    final first = pagePixelSize(
      quad: a4.quad,
      imageWidth: 3000,
      imageHeight: 4000,
    );
    final secondNatural = pagePixelSize(
      quad: receipt.quad,
      imageWidth: 3000,
      imageHeight: 4000,
    );
    expect(secondNatural.width, isNot(first.width));
    final shared = documentPixelSize([first, secondNatural]);
    final pageA = warpPerspective(
      a4.image,
      a4.quad,
      forceWidth: shared.width,
      forceHeight: shared.height,
    );
    final pageB = warpPerspective(
      receipt.image,
      receipt.quad,
      forceWidth: shared.width,
      forceHeight: shared.height,
    );
    expect(pageA.width, shared.width);
    expect(pageA.height, shared.height);
    expect(pageB.width, pageA.width);
    expect(pageB.height, pageA.height);
  });

  test('writes the page-shape comparison figure', () {
    final steep = _project(
      pageW: 210,
      pageH: 297,
      imageW: 520,
      imageH: 680,
      f: 760,
      distance: 480,
      yaw: 0.48,
      pitch: 0.7,
      roll: 0.05,
      grid: 18,
    );
    final rotated = _project(
      pageW: 210,
      pageH: 297,
      imageW: 520,
      imageH: 680,
      f: 900,
      distance: 560,
      yaw: 0.02,
      pitch: 0.04,
      roll: 0.18,
      grid: 18,
    );
    final receipt = _project(
      pageW: 74,
      pageH: 222,
      imageW: 520,
      imageH: 680,
      f: 820,
      distance: 430,
      yaw: -0.28,
      pitch: 0.33,
      roll: -0.04,
      grid: 12,
    );
    expect(steep.inside && rotated.inside && receipt.inside, isTrue);

    const cell = 250;
    const labelH = 36;
    const gutter = 8;
    final rows = [steep, rotated, receipt];
    final board = img.Image(
      width: gutter + 3 * (cell + gutter),
      height: gutter + rows.length * (cell + labelH + gutter),
      numChannels: 3,
    );
    img.fill(board, color: img.ColorRgb8(232, 236, 242));

    for (var row = 0; row < rows.length; row++) {
      final scene = rows[row];
      final top = gutter + row * (cell + labelH + gutter);
      final exportNew = pagePixelSize(
        quad: scene.quad,
        imageWidth: 3000,
        imageHeight: 4000,
      );
      final exportOld = legacyEdgeSize(
        quad: scene.quad,
        imageWidth: 3000,
        imageHeight: 4000,
      );
      final oldVisual = _fit(
        warpPerspective(
          scene.image,
          scene.quad,
          forceWidth: _fitEdge(exportOld.width, exportOld.height, 280).$1,
          forceHeight: _fitEdge(exportOld.width, exportOld.height, 280).$2,
          inset: false,
        ),
        cell,
      );
      final fitted = _fitEdge(exportNew.width, exportNew.height, 280);
      final newVisual = _fit(
        warpPerspective(
          scene.image,
          scene.quad,
          forceWidth: fitted.$1,
          forceHeight: fitted.$2,
        ),
        cell,
      );
      final photos = [
        (scene.image, 'input'),
        (oldVisual, '${exportOld.width} x ${exportOld.height}'),
        (newVisual, '${exportNew.width} x ${exportNew.height}'),
      ];
      for (var col = 0; col < photos.length; col++) {
        final left = gutter + col * (cell + gutter);
        _blitContain(board, photos[col].$1, left, top, cell, cell);
        img.drawString(
          board,
          photos[col].$2,
          font: img.arial14,
          x: left + 6,
          y: top + cell + 8,
          color: img.ColorRgb8(15, 23, 42),
        );
      }
    }

    final bytes = img.encodePng(board);
    final file = File('build/fix/page-shape.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(1000));
  });
}

(int, int) _fitEdge(int width, int height, int maxEdge) {
  final long = math.max(width, height);
  if (long <= maxEdge) return (width, height);
  final scale = maxEdge / long;
  return (
    math.max(1, (width * scale).round()),
    math.max(1, (height * scale).round()),
  );
}

img.Image _fit(img.Image source, int maxEdge) {
  final fitted = _fitEdge(source.width, source.height, maxEdge);
  if (fitted.$1 == source.width && fitted.$2 == source.height) return source;
  return img.copyResize(
    source,
    width: fitted.$1,
    height: fitted.$2,
    interpolation: img.Interpolation.linear,
  );
}

void _blitContain(
  img.Image board,
  img.Image sprite,
  int left,
  int top,
  int boxW,
  int boxH,
) {
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
  final resized = img.copyResize(
    sprite,
    width: w,
    height: h,
    interpolation: img.Interpolation.linear,
  );
  img.compositeImage(
    board,
    resized,
    dstX: left + (boxW - w) ~/ 2,
    dstY: top + (boxH - h) ~/ 2,
  );
}

class _Scene {
  _Scene(this.image, this.quad, this.inside);
  final img.Image image;
  final Quad quad;
  final bool inside;
}

_Scene _project({
  required double pageW,
  required double pageH,
  required int imageW,
  required int imageH,
  required double f,
  required double distance,
  required double yaw,
  required double pitch,
  required double roll,
  int grid = 0,
}) {
  final cx = (imageW - 1) / 2;
  final cy = (imageH - 1) / 2;

  (double, double, double) place(double u, double v) {
    final x = (u - 0.5) * pageW;
    final y = (v - 0.5) * pageH;
    final cr = math.cos(roll);
    final sr = math.sin(roll);
    final x1 = cr * x - sr * y;
    final y1 = sr * x + cr * y;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final y2 = cp * y1;
    final z2 = sp * y1;
    final cyaw = math.cos(yaw);
    final syaw = math.sin(yaw);
    final x3 = cyaw * x1 + syaw * z2;
    final z3 = -syaw * x1 + cyaw * z2;
    return (x3, y2, z3 + distance);
  }

  ({double x, double y})? projectPoint(double u, double v) {
    final p = place(u, v);
    if (p.$3.abs() < 1e-6) return null;
    return (x: cx + f * p.$1 / p.$3, y: cy + f * p.$2 / p.$3);
  }

  NormPoint norm(({double x, double y}) p) => NormPoint(
    (p.x / (imageW - 1)).clamp(0.0, 1.0),
    (p.y / (imageH - 1)).clamp(0.0, 1.0),
  );

  final c00 = projectPoint(0, 0);
  final c10 = projectPoint(1, 0);
  final c11 = projectPoint(1, 1);
  final c01 = projectPoint(0, 1);
  if (c00 == null || c10 == null || c11 == null || c01 == null) {
    return _Scene(
      img.Image(width: imageW, height: imageH, numChannels: 3),
      Quad.standard,
      false,
    );
  }
  bool inFrame(({double x, double y}) p) =>
      p.x >= 8 && p.y >= 8 && p.x <= imageW - 9 && p.y <= imageH - 9;
  final inside =
      inFrame(c00) && inFrame(c10) && inFrame(c11) && inFrame(c01);

  final p0 = place(0, 0);
  final p1 = place(1, 0);
  final p2 = place(0, 1);
  final e1 = (p1.$1 - p0.$1, p1.$2 - p0.$2, p1.$3 - p0.$3);
  final e2 = (p2.$1 - p0.$1, p2.$2 - p0.$2, p2.$3 - p0.$3);
  final normal = (
    e1.$2 * e2.$3 - e1.$3 * e2.$2,
    e1.$3 * e2.$1 - e1.$1 * e2.$3,
    e1.$1 * e2.$2 - e1.$2 * e2.$1,
  );
  final uu = e1.$1 * e1.$1 + e1.$2 * e1.$2 + e1.$3 * e1.$3;
  final vv = e2.$1 * e2.$1 + e2.$2 * e2.$2 + e2.$3 * e2.$3;
  final uv = e1.$1 * e2.$1 + e1.$2 * e2.$2 + e1.$3 * e2.$3;
  final det = uu * vv - uv * uv;

  final image = img.Image(width: imageW, height: imageH, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(55, 48, 42));
  final texW = 420;
  final texH = math.max(8, (texW * pageH / pageW).round());

  for (var y = 0; y < imageH; y++) {
    for (var x = 0; x < imageW; x++) {
      final dir = (x - cx, y - cy, f);
      final denom = normal.$1 * dir.$1 + normal.$2 * dir.$2 + normal.$3 * dir.$3;
      if (denom.abs() < 1e-8) continue;
      final t = (normal.$1 * p0.$1 + normal.$2 * p0.$2 + normal.$3 * p0.$3) /
          denom;
      if (t <= 0) continue;
      final hit = (dir.$1 * t, dir.$2 * t, dir.$3 * t);
      final d = (hit.$1 - p0.$1, hit.$2 - p0.$2, hit.$3 - p0.$3);
      final du = d.$1 * e1.$1 + d.$2 * e1.$2 + d.$3 * e1.$3;
      final dv = d.$1 * e2.$1 + d.$2 * e2.$2 + d.$3 * e2.$3;
      final u = (du * vv - dv * uv) / det;
      final v = (dv * uu - du * uv) / det;
      if (u < 0 || v < 0 || u > 1 || v > 1) continue;
      final color = _pageColor(u, v, texW, texH, grid);
      image.setPixelRgb(x, y, color.$1, color.$2, color.$3);
    }
  }

  return _Scene(
    image,
    Quad(
      topLeft: norm(c00),
      topRight: norm(c10),
      bottomRight: norm(c11),
      bottomLeft: norm(c01),
    ),
    inside,
  );
}

(int, int, int) _pageColor(double u, double v, int texW, int texH, int grid) {
  final px = u * (texW - 1);
  final py = v * (texH - 1);
  if (px < 6 || py < 6 || px > texW - 7 || py > texH - 7) {
    return (30, 64, 175);
  }
  if (grid > 0) {
    final col = px % grid;
    final row = py % grid;
    if (col < 1.2 || row < 1.2) return (37, 99, 235);
  }
  if (u > 0.08 && u < 0.62 && v > 0.08 && v < 0.16) {
    return (15, 23, 42);
  }
  return (246, 244, 238);
}
