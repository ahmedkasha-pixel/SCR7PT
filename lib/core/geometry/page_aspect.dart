import 'dart:math' as math;

import '../app_config.dart';
import '../../data/models/records.dart';
import 'quad.dart';

/// Long side over short side of ISO A4 (297 / 210).
const double a4Ratio = 297 / 210;

/// Long side over short side of US Letter (11 / 8.5).
const double letterRatio = 11 / 8.5;

/// Relative window for snapping a recovered ratio onto A4 or Letter.
const double paperSnapTolerance = 0.06;

/// 300 dpi A4, rounded to whole pixels (210 mm × 297 mm).
const int a4ShortPx = 2480;
const int a4LongPx = 3508;

/// 300 dpi US Letter (8.5 in × 11 in).
const int letterShortPx = 2550;
const int letterLongPx = 3300;

/// Pull each corner this far toward the quad center before sampling,
/// so a sliver of background does not survive the warp.
const double pageBorderInset = 0.0075;

/// Recovered shape of a rectangular page.
class PageGeometry {
  const PageGeometry({
    required this.longOverShort,
    required this.portrait,
    required this.fromVanishingPoints,
  });

  /// Physical long edge divided by the physical short edge. Always ≥ 1.
  final double longOverShort;

  /// True when the page's side edges are the longer physical edges.
  final bool portrait;

  /// True when the focal-length / vanishing-point method succeeded.
  final bool fromVanishingPoints;
}

/// Inset [quad] toward its centroid. The output aspect stays exact because
/// the warp target is still the recovered rectangle.
Quad insetPageQuad(Quad quad, [double fraction = pageBorderInset]) {
  final points = quad.points;
  var cx = 0.0;
  var cy = 0.0;
  for (final point in points) {
    cx += point.x;
    cy += point.y;
  }
  cx /= points.length;
  cy /= points.length;
  NormPoint pull(NormPoint point) => NormPoint(
    point.x + (cx - point.x) * fraction,
    point.y + (cy - point.y) * fraction,
  );
  return Quad(
    topLeft: pull(quad.topLeft),
    topRight: pull(quad.topRight),
    bottomRight: pull(quad.bottomRight),
    bottomLeft: pull(quad.bottomLeft),
  );
}

/// Aspect of the physical page from the four image corners.
///
/// Opposite edges meet at two vanishing points. With the principal point at
/// the image center, the focal length follows Zhang and He's whiteboard
/// relation f² = −(vh − c) · (vv − c). The corners are then back-projected
/// onto that plane and the rectangle's edge lengths are measured in 3D.
/// Parallel edges (a page facing the camera) fall back to image edge lengths,
/// which already match the true ratio when there is no foreshortening.
PageGeometry recoverPageGeometry({
  required Quad quad,
  required int imageWidth,
  required int imageHeight,
}) {
  final tl = _pixel(quad.topLeft, imageWidth, imageHeight);
  final tr = _pixel(quad.topRight, imageWidth, imageHeight);
  final br = _pixel(quad.bottomRight, imageWidth, imageHeight);
  final bl = _pixel(quad.bottomLeft, imageWidth, imageHeight);
  final top = (_dist(tl, tr) + _dist(bl, br)) / 2;
  final side = (_dist(tl, bl) + _dist(tr, br)) / 2;
  PageGeometry edges() {
    final portrait = side >= top;
    final short = math.max(1e-6, math.min(top, side));
    return PageGeometry(
      longOverShort: math.max(top, side) / short,
      portrait: portrait,
      fromVanishingPoints: false,
    );
  }

  final scale = math.max(imageWidth, imageHeight).toDouble();
  final vh = _intersect(tl, tr, bl, br, scale);
  final vv = _intersect(tl, bl, tr, br, scale);
  if (vh == null || vv == null) return edges();

  final cx = (imageWidth - 1) / 2;
  final cy = (imageHeight - 1) / 2;
  final f2 = -((vh.x - cx) * (vv.x - cx) + (vh.y - cy) * (vv.y - cy));
  if (f2 < 1) return edges();
  final f = math.sqrt(f2);

  final dh = _ray(vh, cx, cy, f);
  final dv = _ray(vv, cx, cy, f);
  final normal = _cross(dh, dv);
  final nLen = _len3(normal);
  if (nLen < 1e-8) return edges();
  final n = (normal.$1 / nLen, normal.$2 / nLen, normal.$3 / nLen);

  (double, double, double)? onPlane(_Px point) {
    final raw = (point.x - cx, point.y - cy, f);
    final denom = n.$1 * raw.$1 + n.$2 * raw.$2 + n.$3 * raw.$3;
    if (denom.abs() < 1e-8) return null;
    final s = 1 / denom;
    return (raw.$1 * s, raw.$2 * s, raw.$3 * s);
  }

  final ptl = onPlane(tl);
  final ptr = onPlane(tr);
  final pbr = onPlane(br);
  final pbl = onPlane(bl);
  if (ptl == null || ptr == null || pbr == null || pbl == null) return edges();

  final width = (_dist3(ptl, ptr) + _dist3(pbl, pbr)) / 2;
  final height = (_dist3(ptl, pbl) + _dist3(ptr, pbr)) / 2;
  if (width < 1e-8 || height < 1e-8) return edges();
  return PageGeometry(
    longOverShort: math.max(width, height) / math.min(width, height),
    portrait: height >= width,
    fromVanishingPoints: true,
  );
}

/// Pixel size of the straightened page.
///
/// Auto snaps to A4 or Letter when the recovered ratio is within
/// [paperSnapTolerance]. A full-resolution capture (long side ≥ 1600, or a
/// measured page edge ≥ 2000) uses the 300 dpi paper size. Smaller frames keep
/// that exact ratio at the captured edge length so a thumbnail is not upscaled.
({int width, int height}) pagePixelSize({
  required Quad quad,
  required int imageWidth,
  required int imageHeight,
  PageSizeMode mode = PageSizeMode.auto,
}) {
  if (quad.isNearFullFrame()) {
    return _cap(imageWidth, imageHeight);
  }
  final geometry = recoverPageGeometry(
    quad: quad,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
  final tl = _pixel(quad.topLeft, imageWidth, imageHeight);
  final tr = _pixel(quad.topRight, imageWidth, imageHeight);
  final br = _pixel(quad.bottomRight, imageWidth, imageHeight);
  final bl = _pixel(quad.bottomLeft, imageWidth, imageHeight);
  final measuredLong = math.max(
    math.max(_dist(tl, tr), _dist(bl, br)),
    math.max(_dist(tl, bl), _dist(tr, br)),
  );
  return sizeForGeometry(
    geometry: geometry,
    mode: mode,
    measuredLong: measuredLong,
    sourceLong: math.max(imageWidth, imageHeight),
  );
}

/// Previous warp: the destination rectangle uses image-space edge lengths,
/// which stretches a page that was photographed at an angle.
({int width, int height}) legacyEdgeSize({
  required Quad quad,
  required int imageWidth,
  required int imageHeight,
}) {
  if (quad.isNearFullFrame()) return _cap(imageWidth, imageHeight);
  final tl = _pixel(quad.topLeft, imageWidth, imageHeight);
  final tr = _pixel(quad.topRight, imageWidth, imageHeight);
  final br = _pixel(quad.bottomRight, imageWidth, imageHeight);
  final bl = _pixel(quad.bottomLeft, imageWidth, imageHeight);
  final width = math.max(32, math.max(_dist(tl, tr), _dist(bl, br)).round());
  final height = math.max(32, math.max(_dist(tl, bl), _dist(tr, br)).round());
  return _cap(width, height);
}

({int width, int height}) sizeForGeometry({
  required PageGeometry geometry,
  required PageSizeMode mode,
  required double measuredLong,
  required int sourceLong,
}) {
  final paper = _paperFor(geometry.longOverShort, mode);
  final fullRes = sourceLong >= 1600 || measuredLong >= 2000;
  late double longSide;
  late double shortSide;
  if (paper == null) {
    longSide = measuredLong.clamp(32, AppConfig.maxImageEdge.toDouble());
    shortSide = longSide / geometry.longOverShort;
  } else if (fullRes) {
    longSide = paper == _Paper.a4 ? a4LongPx.toDouble() : letterLongPx.toDouble();
    shortSide = paper == _Paper.a4
        ? a4ShortPx.toDouble()
        : letterShortPx.toDouble();
  } else {
    longSide = measuredLong.clamp(32, AppConfig.maxImageEdge.toDouble());
    final ratio = paper == _Paper.a4 ? a4Ratio : letterRatio;
    shortSide = longSide / ratio;
  }
  final width = geometry.portrait ? shortSide : longSide;
  final height = geometry.portrait ? longSide : shortSide;
  return _cap(width.round(), height.round());
}

/// Every page in one document shares the first page's pixel size.
({int width, int height}) documentPixelSize(
  List<({int width, int height})> pages,
) {
  if (pages.isEmpty) return (width: a4ShortPx, height: a4LongPx);
  return pages.first;
}

enum _Paper { a4, letter }

_Paper? _paperFor(double ratio, PageSizeMode mode) {
  switch (mode) {
    case PageSizeMode.a4:
      return _Paper.a4;
    case PageSizeMode.letter:
      return _Paper.letter;
    case PageSizeMode.original:
      return null;
    case PageSizeMode.auto:
      if ((ratio - a4Ratio).abs() / a4Ratio <= paperSnapTolerance) {
        return _Paper.a4;
      }
      if ((ratio - letterRatio).abs() / letterRatio <= paperSnapTolerance) {
        return _Paper.letter;
      }
      return null;
  }
}

({int width, int height}) _cap(int width, int height) {
  final longEdge = math.max(width, height);
  if (longEdge <= AppConfig.maxImageEdge) {
    return (width: math.max(1, width), height: math.max(1, height));
  }
  final scale = AppConfig.maxImageEdge / longEdge;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

class _Px {
  const _Px(this.x, this.y);
  final double x;
  final double y;
}

_Px _pixel(NormPoint point, int width, int height) => _Px(
  point.x.clamp(0.0, 1.0) * (width - 1),
  point.y.clamp(0.0, 1.0) * (height - 1),
);

double _dist(_Px a, _Px b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _dist3((double, double, double) a, (double, double, double) b) {
  final dx = a.$1 - b.$1;
  final dy = a.$2 - b.$2;
  final dz = a.$3 - b.$3;
  return math.sqrt(dx * dx + dy * dy + dz * dz);
}

double _len3((double, double, double) v) =>
    math.sqrt(v.$1 * v.$1 + v.$2 * v.$2 + v.$3 * v.$3);

(double, double, double) _ray(_Px point, double cx, double cy, double f) {
  final x = point.x - cx;
  final y = point.y - cy;
  final len = math.sqrt(x * x + y * y + f * f);
  return (x / len, y / len, f / len);
}

(double, double, double) _cross(
  (double, double, double) a,
  (double, double, double) b,
) => (
  a.$2 * b.$3 - a.$3 * b.$2,
  a.$3 * b.$1 - a.$1 * b.$3,
  a.$1 * b.$2 - a.$2 * b.$1,
);

_Px? _intersect(_Px p1, _Px p2, _Px q1, _Px q2, double scale) {
  final dx1 = p2.x - p1.x;
  final dy1 = p2.y - p1.y;
  final dx2 = q2.x - q1.x;
  final dy2 = q2.y - q1.y;
  final denom = dx1 * dy2 - dy1 * dx2;
  if (denom.abs() < 1e-6 * scale) return null;
  final t = ((q1.x - p1.x) * dy2 - (q1.y - p1.y) * dx2) / denom;
  final point = _Px(p1.x + t * dx1, p1.y + t * dy1);
  final reach = _dist(point, _Px(scale / 2, scale / 2));
  if (reach > scale * 80) return null;
  return point;
}
