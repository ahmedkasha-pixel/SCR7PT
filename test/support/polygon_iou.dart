/// Exact IoU of two convex quadrilaterals given as `[x0, y0, ..., x3, y3]`.
///
/// Same metric as the Python prototype (shapely polygon intersection over
/// union), using Sutherland-Hodgman clipping for convex polygons.
double polygonIoU(List<double> a, List<double> b) {
  final pa = _ccw(_points(a));
  final pb = _ccw(_points(b));
  final areaA = _area(pa).abs();
  final areaB = _area(pb).abs();
  final inter = _area(_clip(pa, pb)).abs();
  final union = areaA + areaB - inter;
  return union > 0 ? inter / union : 0.0;
}

List<(double, double)> _points(List<double> v) => [
  for (var i = 0; i + 1 < v.length; i += 2) (v[i], v[i + 1]),
];

double _area(List<(double, double)> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i];
    final b = p[(i + 1) % p.length];
    s += a.$1 * b.$2 - b.$1 * a.$2;
  }
  return s / 2;
}

List<(double, double)> _ccw(List<(double, double)> p) =>
    _area(p) < 0 ? p.reversed.toList() : p;

List<(double, double)> _clip(
  List<(double, double)> subject,
  List<(double, double)> clipper,
) {
  var output = subject;
  for (var i = 0; i < clipper.length && output.isNotEmpty; i++) {
    final c1 = clipper[i];
    final c2 = clipper[(i + 1) % clipper.length];
    bool inside((double, double) p) =>
        (c2.$1 - c1.$1) * (p.$2 - c1.$2) - (c2.$2 - c1.$2) * (p.$1 - c1.$1) >= 0;
    (double, double) cross((double, double) p, (double, double) q) {
      final a1 = c2.$2 - c1.$2;
      final b1 = c1.$1 - c2.$1;
      final d1 = a1 * c1.$1 + b1 * c1.$2;
      final a2 = q.$2 - p.$2;
      final b2 = p.$1 - q.$1;
      final d2 = a2 * p.$1 + b2 * p.$2;
      final det = a1 * b2 - a2 * b1;
      return ((b2 * d1 - b1 * d2) / det, (a1 * d2 - a2 * d1) / det);
    }

    final input = output;
    output = [];
    for (var j = 0; j < input.length; j++) {
      final cur = input[j];
      final prev = input[(j + input.length - 1) % input.length];
      if (inside(cur)) {
        if (!inside(prev)) output.add(cross(prev, cur));
        output.add(cur);
      } else if (inside(prev)) {
        output.add(cross(prev, cur));
      }
    }
  }
  return output;
}
