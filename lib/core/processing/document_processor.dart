import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../app_config.dart';
import '../geometry/page_aspect.dart';
import '../geometry/quad.dart';
import '../../data/models/records.dart';
import 'enhance.dart';

/// Result of preparing a captured or imported photo for editing.
class PreparedPage {
  PreparedPage({
    required this.originalJpeg,
    required this.previewJpeg,
    required this.corners,
    required this.width,
    required this.height,
  });

  final Uint8List originalJpeg;
  final Uint8List previewJpeg;
  final List<double> corners;
  final int width;
  final int height;
}

/// Arguments for re-rendering a stored page on a background isolate.
class RenderRequest {
  RenderRequest({
    required this.originalJpeg,
    required this.corners,
    required this.filterName,
    this.pageSizeMode = 'auto',
    this.forceWidth,
    this.forceHeight,
  });

  final Uint8List originalJpeg;
  final List<double> corners;
  final String filterName;
  final String pageSizeMode;
  final int? forceWidth;
  final int? forceHeight;
}

/// Arguments for [preparePageRequest] on a background isolate.
class PrepareRequest {
  PrepareRequest(this.bytes, this.pageSizeMode, {this.detectedQuad});

  final Uint8List bytes;
  final String pageSizeMode;
  final List<double>? detectedQuad;
}

/// Decode at capture resolution, detect edges, and preview the default filter.
PreparedPage preparePage(Uint8List bytes, {Quad? detectedQuad}) {
  return preparePageRequest(
    PrepareRequest(
      bytes,
      PageSizeMode.auto.name,
      detectedQuad: detectedQuad?.toList(),
    ),
  );
}

PreparedPage preparePageRequest(PrepareRequest request) {
  // Fast decode for JPEG orientation/dimensions
  final decoded = _decodeFull(request.bytes);
  final Quad quad;
  if (request.detectedQuad != null) {
    // When live-detected quad is provided from viewfinder tracking,
    // trust it immediately for instant transition.
    final live = Quad.fromList(request.detectedQuad!);
    quad = live.isUsable ? live : tryDetectQuad(decoded) ?? Quad.standard;
  } else {
    quad = tryDetectQuad(decoded) ?? Quad.standard;
  }

  final mode = PageSizeMode.values.asNameMap()[request.pageSizeMode] ??
      PageSizeMode.auto;
  final preview = renderImage(
    decoded,
    quad,
    PageFilter.autoEnhance,
    pageSize: mode,
  );
  final original = _isJpeg(request.bytes)
      ? request.bytes
      : Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  return PreparedPage(
    originalJpeg: original,
    previewJpeg: Uint8List.fromList(
      img.encodeJpg(preview, quality: AppConfig.jpegQuality),
    ),
    corners: quad.toList(),
    width: decoded.width,
    height: decoded.height,
  );
}

/// Instant preparation for captured photo: extracts orientation-baked width/height,
/// uses detected quad directly, and creates initial thumbnail preview instantly without
/// heavy full-resolution warp.
PreparedPage preparePageInstant(Uint8List bytes, {Quad? detectedQuad}) {
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  int width = info?.width ?? 1200;
  int height = info?.height ?? 1600;

  final quad = (detectedQuad != null && detectedQuad.isUsable)
      ? detectedQuad
      : Quad.standard;

  return PreparedPage(
    originalJpeg: bytes,
    previewJpeg: bytes,
    corners: quad.toList(),
    width: width,
    height: height,
  );
}

Uint8List renderRequest(RenderRequest request) {
  return renderJpeg(
    request.originalJpeg,
    Quad.fromList(request.corners),
    PageFilter.values.byName(request.filterName),
    pageSize: PageSizeMode.values.byName(request.pageSizeMode),
    forceWidth: request.forceWidth,
    forceHeight: request.forceHeight,
  );
}

Uint8List renderJpeg(
  Uint8List originalJpeg,
  Quad quad,
  PageFilter filter, {
  PageSizeMode pageSize = PageSizeMode.auto,
  int? forceWidth,
  int? forceHeight,
}) {
  final decoded = img.decodeImage(originalJpeg);
  if (decoded == null) {
    throw const FormatException('unsupported-image');
  }
  final rgb = decoded.convert(format: img.Format.uint8, numChannels: 3);
  final rendered = renderImage(
    rgb,
    quad,
    filter,
    pageSize: pageSize,
    forceWidth: forceWidth,
    forceHeight: forceHeight,
  );
  return Uint8List.fromList(
    img.encodeJpg(rendered, quality: AppConfig.jpegQuality),
  );
}

img.Image renderImage(
  img.Image source,
  Quad quad,
  PageFilter filter, {
  PageSizeMode pageSize = PageSizeMode.auto,
  int? forceWidth,
  int? forceHeight,
}) {
  final img.Image base;
  if (quad.isNearFullFrame() && forceWidth == null) {
    base = source;
  } else if (quad.isNearFullFrame() && forceWidth != null) {
    base = img.copyResize(
      source,
      width: forceWidth,
      height: forceHeight ?? forceWidth,
      interpolation: img.Interpolation.linear,
    );
  } else {
    base = warpPerspective(
      source,
      quad,
      mode: pageSize,
      forceWidth: forceWidth,
      forceHeight: forceHeight,
    );
  }
  return applyFilter(base, filter);
}

img.Image applyFilter(img.Image source, PageFilter filter) {
  final rgb = source.convert(format: img.Format.uint8, numChannels: 3);
  switch (filter) {
    case PageFilter.autoEnhance:
      return autoEnhance(rgb);
    case PageFilter.original:
      return rgb;
    case PageFilter.grayscale:
      return grayscaleNormalized(rgb);
    case PageFilter.blackAndWhite:
      return blackAndWhiteAdaptive(rgb);
    case PageFilter.brighten:
      return _map(rgb, (r, g, b) {
        int lift(int channel) => (channel * 1.15 + 18).round().clamp(0, 255);
        return (lift(r), lift(g), lift(b));
      });
  }
}

/// Finds a document quadrilateral. Falls back to [Quad.standard].
Quad detectQuad(img.Image source) {
  return tryDetectQuad(source) ?? Quad.standard;
}

/// Finds a document quadrilateral if confident, otherwise returns null.
Quad? tryDetectQuad(img.Image source) {
  final work = _downscale(source, 480);
  final view = _Rgb(work);
  final gray = Uint8List(view.width * view.height);
  for (var y = 0; y < view.height; y++) {
    for (var x = 0; x < view.width; x++) {
      gray[y * view.width + x] = view.luma(x, y);
    }
  }
  final blurred = _boxBlur(gray, view.width, view.height);
  final magnitude = _sobel(blurred, view.width, view.height);
  var maxMag = 0;
  for (final value in magnitude) {
    if (value > maxMag) maxMag = value;
  }
  if (maxMag < 40) return null;

  final threshold = math.max(30, (maxMag * 0.22).round());
  final points = <_Pt>[];
  for (var y = 1; y < view.height - 1; y++) {
    for (var x = 1; x < view.width - 1; x++) {
      if (magnitude[y * view.width + x] >= threshold) {
        points.add(_Pt(x.toDouble(), y.toDouble()));
      }
    }
  }
  if (points.length < 30) return null;

  final sample = points.length > 6000
      ? [
          for (var i = 0; i < points.length; i += points.length ~/ 6000)
            points[i],
        ]
      : points;
  final hull = _convexHull(sample);
  if (hull.length < 4) return null;

  final quad = Quad.fromUnordered([
    for (final corner in _extremeCorners(hull))
      NormPoint(corner.x / (view.width - 1), corner.y / (view.height - 1)),
  ]);
  return quad.isUsable ? quad : null;
}

img.Image warpPerspective(
  img.Image source,
  Quad quad, {
  PageSizeMode mode = PageSizeMode.auto,
  int? forceWidth,
  int? forceHeight,
  bool inset = true,
}) {
  final rgb = source.convert(format: img.Format.uint8, numChannels: 3);
  final view = _Rgb(rgb);
  final sampling = inset ? insetPageQuad(quad) : quad;
  final tl = _denorm(sampling.topLeft, view.width, view.height);
  final tr = _denorm(sampling.topRight, view.width, view.height);
  final br = _denorm(sampling.bottomRight, view.width, view.height);
  final bl = _denorm(sampling.bottomLeft, view.width, view.height);

  final size = (forceWidth != null && forceHeight != null)
      ? (width: math.max(1, forceWidth), height: math.max(1, forceHeight))
      : pagePixelSize(
          quad: quad,
          imageWidth: view.width,
          imageHeight: view.height,
          mode: mode,
        );
  final outW = size.width;
  final outH = size.height;

  final homography = _homography(
    from: [
      _Pt(0, 0),
      _Pt((outW - 1).toDouble(), 0),
      _Pt((outW - 1).toDouble(), (outH - 1).toDouble()),
      _Pt(0, (outH - 1).toDouble()),
    ],
    to: [tl, tr, br, bl],
  );

  final output = img.Image(width: outW, height: outH, numChannels: 3);
  final dest = _Rgb(output);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final sample = _apply(homography, x.toDouble(), y.toDouble());
      final color = view.sample(sample.x, sample.y);
      dest.set(x, y, color.$1, color.$2, color.$3);
    }
  }
  return output;
}

/// Pixel size of the warped page. The aspect comes from the vanishing-point
/// recovery in [pagePixelSize], then snaps to A4 or Letter when [mode] asks.
({int width, int height}) warpOutputSize({
  required int sourceWidth,
  required int sourceHeight,
  required Quad quad,
  PageSizeMode mode = PageSizeMode.auto,
}) {
  return pagePixelSize(
    quad: quad,
    imageWidth: sourceWidth,
    imageHeight: sourceHeight,
    mode: mode,
  );
}

/// A4 page photographed straight-on by a 12 MP sensor (3000×4000 portrait).
///
/// Auto page size snaps that ratio to 300 dpi A4 (2480×3508). The long side
/// stays well above 2000 px.
({int width, int height}) a4ExportSizeFrom12Mp() {
  const sourceWidth = 3000;
  const sourceHeight = 4000;
  final pageWidth = (sourceHeight * 210 / 297).round();
  final inset = (sourceWidth - pageWidth) / 2 / sourceWidth;
  final quad = Quad(
    topLeft: NormPoint(inset, 0),
    topRight: NormPoint(1 - inset, 0),
    bottomRight: NormPoint(1 - inset, 1),
    bottomLeft: NormPoint(inset, 1),
  );
  return warpOutputSize(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    quad: quad,
  );
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;

img.Image _decodeFull(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('unsupported-image');
  }
  final oriented = img.bakeOrientation(decoded);
  final rgb = oriented.convert(format: img.Format.uint8, numChannels: 3);
  return _downscale(rgb, AppConfig.maxImageEdge);
}

img.Image _downscale(img.Image source, int maxEdge) {
  final longEdge = math.max(source.width, source.height);
  if (longEdge <= maxEdge) return source;
  final scale = maxEdge / longEdge;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}

img.Image _map(
  img.Image source,
  (int, int, int) Function(int r, int g, int b) transform,
) {
  final view = _Rgb(source);
  final output = img.Image(
    width: view.width,
    height: view.height,
    numChannels: 3,
  );
  final dest = _Rgb(output);
  for (var y = 0; y < view.height; y++) {
    for (var x = 0; x < view.width; x++) {
      final color = transform(view.r(x, y), view.g(x, y), view.b(x, y));
      dest.set(x, y, color.$1, color.$2, color.$3);
    }
  }
  return output;
}

int _luma(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round();

Uint8List _boxBlur(Uint8List src, int width, int height) {
  final temp = Uint8List(src.length);
  final dest = Uint8List(src.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final x0 = math.max(0, x - 1);
      final x1 = math.min(width - 1, x + 1);
      var sum = 0;
      for (var i = x0; i <= x1; i++) {
        sum += src[y * width + i];
      }
      temp[y * width + x] = (sum / (x1 - x0 + 1)).round();
    }
  }
  for (var y = 0; y < height; y++) {
    final y0 = math.max(0, y - 1);
    final y1 = math.min(height - 1, y + 1);
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var i = y0; i <= y1; i++) {
        sum += temp[i * width + x];
      }
      dest[y * width + x] = (sum / (y1 - y0 + 1)).round();
    }
  }
  return dest;
}

Int32List _sobel(Uint8List gray, int width, int height) {
  final mag = Int32List(gray.length);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      int at(int px, int py) => gray[py * width + px];
      final gx =
          -at(x - 1, y - 1) +
          at(x + 1, y - 1) +
          -2 * at(x - 1, y) +
          2 * at(x + 1, y) +
          -at(x - 1, y + 1) +
          at(x + 1, y + 1);
      final gy =
          -at(x - 1, y - 1) -
          2 * at(x, y - 1) -
          at(x + 1, y - 1) +
          at(x - 1, y + 1) +
          2 * at(x, y + 1) +
          at(x + 1, y + 1);
      mag[y * width + x] = math.max(gx.abs(), gy.abs());
    }
  }
  return mag;
}

class _Pt {
  const _Pt(this.x, this.y);
  final double x;
  final double y;
}

List<_Pt> _convexHull(List<_Pt> points) {
  final sorted = [...points]
    ..sort((a, b) {
      final byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.y.compareTo(b.y);
    });
  final unique = <_Pt>[];
  for (final point in sorted) {
    if (unique.isEmpty ||
        unique.last.x != point.x ||
        unique.last.y != point.y) {
      unique.add(point);
    }
  }
  if (unique.length <= 3) return unique;

  double cross(_Pt o, _Pt a, _Pt b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  final lower = <_Pt>[];
  for (final point in unique) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, point) <= 0) {
      lower.removeLast();
    }
    lower.add(point);
  }
  final upper = <_Pt>[];
  for (final point in unique.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, point) <= 0) {
      upper.removeLast();
    }
    upper.add(point);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

List<_Pt> _extremeCorners(List<_Pt> hull) {
  _Pt pick(double Function(_Pt p) score, bool minimum) {
    var chosen = hull.first;
    var chosenScore = score(chosen);
    for (final point in hull.skip(1)) {
      final value = score(point);
      if (minimum ? value < chosenScore : value > chosenScore) {
        chosen = point;
        chosenScore = value;
      }
    }
    return chosen;
  }

  return [
    pick((p) => p.x + p.y, true),
    pick((p) => p.x - p.y, false),
    pick((p) => p.x + p.y, false),
    pick((p) => p.x - p.y, true),
  ];
}

_Pt _denorm(NormPoint point, int width, int height) => _Pt(
  point.x.clamp(0.0, 1.0) * (width - 1),
  point.y.clamp(0.0, 1.0) * (height - 1),
);

List<double> _homography({required List<_Pt> from, required List<_Pt> to}) {
  final matrix = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i].x;
    final y = from[i].y;
    final u = to[i].x;
    final v = to[i].y;
    final row = i * 2;
    matrix[row][0] = x;
    matrix[row][1] = y;
    matrix[row][2] = 1;
    matrix[row][6] = -u * x;
    matrix[row][7] = -u * y;
    matrix[row][8] = u;
    matrix[row + 1][3] = x;
    matrix[row + 1][4] = y;
    matrix[row + 1][5] = 1;
    matrix[row + 1][6] = -v * x;
    matrix[row + 1][7] = -v * y;
    matrix[row + 1][8] = v;
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    var pivotAbs = matrix[col][col].abs();
    for (var row = col + 1; row < 8; row++) {
      final value = matrix[row][col].abs();
      if (value > pivotAbs) {
        pivotAbs = value;
        pivot = row;
      }
    }
    if (pivotAbs < 1e-8) {
      throw StateError('Could not compute a perspective transform.');
    }
    if (pivot != col) {
      final swap = matrix[col];
      matrix[col] = matrix[pivot];
      matrix[pivot] = swap;
    }
    final divisor = matrix[col][col];
    for (var c = col; c < 9; c++) {
      matrix[col][c] /= divisor;
    }
    for (var row = 0; row < 8; row++) {
      if (row == col) continue;
      final factor = matrix[row][col];
      for (var c = col; c < 9; c++) {
        matrix[row][c] -= factor * matrix[col][c];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) matrix[i][8], 1];
}

_Pt _apply(List<double> h, double x, double y) {
  final w = h[6] * x + h[7] * y + h[8];
  if (w.abs() < 1e-8) return _Pt(x, y);
  return _Pt(
    (h[0] * x + h[1] * y + h[2]) / w,
    (h[3] * x + h[4] * y + h[5]) / w,
  );
}

class _Rgb {
  _Rgb(this.image)
    : bytes = image.toUint8List(),
      width = image.width,
      height = image.height,
      channels = image.numChannels;

  final img.Image image;
  final Uint8List bytes;
  final int width;
  final int height;
  final int channels;

  int _index(int x, int y) => (y * width + x) * channels;

  int r(int x, int y) => bytes[_index(x, y)];
  int g(int x, int y) => bytes[_index(x, y) + 1];
  int b(int x, int y) => bytes[_index(x, y) + 2];

  int luma(int x, int y) => _luma(r(x, y), g(x, y), b(x, y));

  void set(int x, int y, int red, int green, int blue) {
    final index = _index(x, y);
    bytes[index] = red.clamp(0, 255).toInt();
    bytes[index + 1] = green.clamp(0, 255).toInt();
    bytes[index + 2] = blue.clamp(0, 255).toInt();
  }

  (int, int, int) sample(double x, double y) {
    if (x < 0 || y < 0 || x > width - 1 || y > height - 1) {
      return (255, 255, 255);
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);
    final dx = x - x0;
    final dy = y - y0;

    int mix(int c00, int c10, int c01, int c11) {
      final value =
          c00 * (1 - dx) * (1 - dy) +
          c10 * dx * (1 - dy) +
          c01 * (1 - dx) * dy +
          c11 * dx * dy;
      return value.round().clamp(0, 255);
    }

    return (
      mix(r(x0, y0), r(x1, y0), r(x0, y1), r(x1, y1)),
      mix(g(x0, y0), g(x1, y0), g(x0, y1), g(x1, y1)),
      mix(b(x0, y0), b(x1, y0), b(x0, y1), b(x1, y1)),
    );
  }
}
