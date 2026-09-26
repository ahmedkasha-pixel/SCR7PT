import 'dart:convert';
import 'dart:math' as math;

/// A point in normalized image space, origin at the top-left.
class NormPoint {
  const NormPoint(this.x, this.y);

  final double x;
  final double y;

  NormPoint clamped() =>
      NormPoint(x.clamp(0.0, 1.0).toDouble(), y.clamp(0.0, 1.0).toDouble());

  List<double> toList() => [x, y];

  @override
  bool operator ==(Object other) =>
      other is NormPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

enum CropCorner { topLeft, topRight, bottomRight, bottomLeft }

/// Four document corners ordered clockwise from the top-left.
class Quad {
  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final NormPoint topLeft;
  final NormPoint topRight;
  final NormPoint bottomRight;
  final NormPoint bottomLeft;

  /// A gentle inset used when no page edges are found.
  static const Quad standard = Quad(
    topLeft: NormPoint(0.07, 0.07),
    topRight: NormPoint(0.93, 0.07),
    bottomRight: NormPoint(0.93, 0.93),
    bottomLeft: NormPoint(0.07, 0.93),
  );

  static const Quad fullFrame = Quad(
    topLeft: NormPoint(0, 0),
    topRight: NormPoint(1, 0),
    bottomRight: NormPoint(1, 1),
    bottomLeft: NormPoint(0, 1),
  );

  List<NormPoint> get points => [topLeft, topRight, bottomRight, bottomLeft];

  NormPoint point(CropCorner corner) {
    switch (corner) {
      case CropCorner.topLeft:
        return topLeft;
      case CropCorner.topRight:
        return topRight;
      case CropCorner.bottomRight:
        return bottomRight;
      case CropCorner.bottomLeft:
        return bottomLeft;
    }
  }

  Quad move(CropCorner corner, NormPoint next) {
    final point = next.clamped();
    switch (corner) {
      case CropCorner.topLeft:
        return Quad(
          topLeft: point,
          topRight: topRight,
          bottomRight: bottomRight,
          bottomLeft: bottomLeft,
        );
      case CropCorner.topRight:
        return Quad(
          topLeft: topLeft,
          topRight: point,
          bottomRight: bottomRight,
          bottomLeft: bottomLeft,
        );
      case CropCorner.bottomRight:
        return Quad(
          topLeft: topLeft,
          topRight: topRight,
          bottomRight: point,
          bottomLeft: bottomLeft,
        );
      case CropCorner.bottomLeft:
        return Quad(
          topLeft: topLeft,
          topRight: topRight,
          bottomRight: bottomRight,
          bottomLeft: point,
        );
    }
  }

  /// Orders four polygon vertices in clockwise order starting from top-left.
  static Quad fromUnordered(List<NormPoint> points) {
    if (points.length != 4) {
      throw ArgumentError('A document quad needs 4 points.');
    }

    // 1. Compute centroid
    final cx = points.map((p) => p.x).reduce((a, b) => a + b) / 4.0;
    final cy = points.map((p) => p.y).reduce((a, b) => a + b) / 4.0;

    // 2. Sort by polar angle around centroid (clockwise)
    final sorted = [...points]..sort((a, b) {
      final angleA = math.atan2(a.y - cy, a.x - cx);
      final angleB = math.atan2(b.y - cy, b.x - cx);
      return angleA.compareTo(angleB);
    });

    // 3. Find the corner closest to top-left (min sum of x + y)
    var tlIdx = 0;
    var minSum = sorted[0].x + sorted[0].y;
    for (var i = 1; i < 4; i++) {
      final s = sorted[i].x + sorted[i].y;
      if (s < minSum) {
        minSum = s;
        tlIdx = i;
      }
    }

    // 4. Arrange in clockwise order: TL, TR, BR, BL
    final tl = sorted[tlIdx];
    final tr = sorted[(tlIdx + 1) % 4];
    final br = sorted[(tlIdx + 2) % 4];
    final bl = sorted[(tlIdx + 3) % 4];

    return Quad(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
    );
  }

  List<double> toList() => [
    topLeft.x,
    topLeft.y,
    topRight.x,
    topRight.y,
    bottomRight.x,
    bottomRight.y,
    bottomLeft.x,
    bottomLeft.y,
  ];

  factory Quad.fromList(List<double> values) {
    if (values.length != 8) {
      return Quad.standard;
    }
    return Quad(
      topLeft: NormPoint(values[0], values[1]),
      topRight: NormPoint(values[2], values[3]),
      bottomRight: NormPoint(values[4], values[5]),
      bottomLeft: NormPoint(values[6], values[7]),
    );
  }

  String toJson() => jsonEncode({
    'tl': topLeft.toList(),
    'tr': topRight.toList(),
    'br': bottomRight.toList(),
    'bl': bottomLeft.toList(),
  });

  factory Quad.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return Quad.standard;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      NormPoint read(String key) {
        final pair = (map[key] as List).cast<num>();
        return NormPoint(pair[0].toDouble(), pair[1].toDouble());
      }

      return Quad(
        topLeft: read('tl'),
        topRight: read('tr'),
        bottomRight: read('br'),
        bottomLeft: read('bl'),
      );
    } catch (_) {
      return Quad.standard;
    }
  }

  /// Area in normalized units (1.0 is the whole image).
  double get area {
    final pts = points;
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  bool isNearFullFrame({double epsilon = 0.02}) {
    bool near(NormPoint point, double x, double y) =>
        (point.x - x).abs() <= epsilon && (point.y - y).abs() <= epsilon;
    return near(topLeft, 0, 0) &&
        near(topRight, 1, 0) &&
        near(bottomRight, 1, 1) &&
        near(bottomLeft, 0, 1);
  }

  bool get isUsable {
    if (area < 0.08) return false;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dx = points[i].x - points[j].x;
        final dy = points[i].y - points[j].y;
        if (math.sqrt(dx * dx + dy * dy) < 0.04) return false;
      }
    }
    return true;
  }

  /// True if the corner coordinates are very close to each other.
  bool isNear(Quad other, {double threshold = 0.05}) {
    double dist(NormPoint a, NormPoint b) =>
        math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
    return dist(topLeft, other.topLeft) < threshold &&
        dist(topRight, other.topRight) < threshold &&
        dist(bottomRight, other.bottomRight) < threshold &&
        dist(bottomLeft, other.bottomLeft) < threshold;
  }

  /// Linear interpolation between this quad and [next] for jitter smoothing.
  Quad lerp(Quad next, double t) {
    NormPoint blend(NormPoint a, NormPoint b) =>
        NormPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
    return Quad(
      topLeft: blend(topLeft, next.topLeft),
      topRight: blend(topRight, next.topRight),
      bottomRight: blend(bottomRight, next.bottomRight),
      bottomLeft: blend(bottomLeft, next.bottomLeft),
    );
  }
}
