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

  /// Orders four unordered points into a clockwise page quad.
  static Quad fromUnordered(List<NormPoint> points) {
    if (points.length != 4) {
      throw ArgumentError('A document quad needs 4 points.');
    }
    NormPoint best(
      double Function(NormPoint p) score, {
      required bool minimum,
    }) {
      var chosen = points.first;
      var chosenScore = score(chosen);
      for (final point in points.skip(1)) {
        final value = score(point);
        if (minimum ? value < chosenScore : value > chosenScore) {
          chosen = point;
          chosenScore = value;
        }
      }
      return chosen;
    }

    return Quad(
      topLeft: best((p) => p.x + p.y, minimum: true),
      topRight: best((p) => p.x - p.y, minimum: false),
      bottomRight: best((p) => p.x + p.y, minimum: false),
      bottomLeft: best((p) => p.x - p.y, minimum: true),
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
}
