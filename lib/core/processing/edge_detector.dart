import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../geometry/quad.dart';

/// Robust multi-stage document edge detector.
///
/// Handles cluttered desks (wood grain, keyboards, mouse/cables, dark cloth),
/// white-on-white tables, rotated documents, and torch glare using multi-channel
/// barrier edge detection, background border flood-fill, and candidate scoring.
class DocumentEdgeDetector {
  static const int targetWorkingEdge = 480;

  /// Detects document corners or returns null if no valid document is framed.
  static Quad? detect(img.Image source) {
    final scale = targetWorkingEdge / math.max(source.width, source.height);
    final workW = math.max(1, (source.width * scale).round());
    final workH = math.max(1, (source.height * scale).round());
    final work = img.copyResize(
      source,
      width: workW,
      height: workH,
      interpolation: img.Interpolation.linear,
    );

    final totalPixels = workW * workH;
    final luma = Uint8List(totalPixels);
    final sat = Float32List(totalPixels);

    var idx = 0;
    for (final pixel in work) {
      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();

      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final delta = maxC - minC;
      sat[idx] = maxC > 0 ? (delta / maxC) : 0.0;
      luma[idx] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
      idx++;
    }

    // 1. Gaussian blur on luma
    final blurred = _gaussianBlur5x5(luma, workW, workH);

    // 2. Candidate barrier edge maps & segmentation masks
    final barriers = <Uint8List>[];

    // Barrier 1: Multi-scale Canny edge detection (low=20, high=60)
    // Excels at physical document edges on white tables & subtle paper borders
    final cannyEdges = _computeCanny(blurred, workW, workH, low: 20, high: 60);
    barriers.add(_morphClose(cannyEdges, workW, workH, 7));

    // Barrier 2: Saturation + luma edges (color boundary between paper and desk)
    final maskSat = Uint8List(totalPixels);
    for (var i = 0; i < totalPixels; i++) {
      if (luma[i] > 130 && sat[i] < 0.28) {
        maskSat[i] = 255;
      }
    }
    final closedSat = _morphClose(maskSat, workW, workH, 9);
    final satEdges = _computeCanny(closedSat, workW, workH, low: 40, high: 120);
    barriers.add(_morphClose(satEdges, workW, workH, 7));

    // Barrier 3: Direct solid saturation mask
    barriers.add(closedSat);

    // 3. Extract & Score Candidate Quads using Border Flood Fill & Direct Segmentation
    final interiorCandidates = <Uint8List>[];
    interiorCandidates.add(_floodFillFromBorder(barriers[0], workW, workH));
    interiorCandidates.add(_floodFillFromBorder(barriers[1], workW, workH));
    interiorCandidates.add(closedSat);

    Quad? bestQuad;
    var bestScore = -1e9;

    for (final rawInterior in interiorCandidates) {
      final interior = _keepLargestConnectedComponent(rawInterior, workW, workH);
      final boundaryPoints = _extractBoundaryPoints(interior, workW, workH);
      if (boundaryPoints.length < 30) continue;

      final hull = _convexHull(boundaryPoints);
      if (hull.length < 4) continue;

      final peri = _polygonPerimeter(hull);

      final candidatePointSets = <List<_Pt>>[];

      // Try multiple RDP approximation tolerances
      for (final epsFactor in [0.02, 0.025, 0.03, 0.035, 0.045, 0.06]) {
        final approx = _approxPolyRDP(hull, epsFactor * peri);
        if (approx.length == 4 && _isConvex(approx)) {
          candidatePointSets.add(approx);
          break; // Found 4-point polygon following true perspective edges
        }
      }

      // Fallback: only if RDP approximation did not find 4 points
      if (candidatePointSets.isEmpty) {
        candidatePointSets.add(_minAreaRectCorners(hull));
        candidatePointSets.add(_extremeCorners(hull));
      }

      for (final quadPts in candidatePointSets) {
        if (quadPts.length != 4) continue;

        final normPts = [
          for (final p in quadPts)
            NormPoint((p.x / (workW - 1)).clamp(0.0, 1.0), (p.y / (workH - 1)).clamp(0.0, 1.0)),
        ];
        final candidateQuad = Quad.fromUnordered(normPts);

        // Validation filters:
        // Area between 12% and 94% of the frame
        final area = candidateQuad.area;
        if (area < 0.12 || area > 0.94) continue;

        // Reject border-hugging quads
        final pts = candidateQuad.points;
        final minX = pts.map((p) => p.x).reduce(math.min);
        final maxX = pts.map((p) => p.x).reduce(math.max);
        final minY = pts.map((p) => p.y).reduce(math.min);
        final maxY = pts.map((p) => p.y).reduce(math.max);
        if (minX < 0.015 && maxX > 0.985 && minY < 0.015 && maxY > 0.985) continue;

        // Angle check (corners roughly 55 - 125 degrees)
        var maxAngleDev = 0.0;
        var totalAngleDev = 0.0;
        for (var i = 0; i < 4; i++) {
          final p0 = pts[(i - 1 + 4) % 4];
          final p1 = pts[i];
          final p2 = pts[(i + 1) % 4];
          final v1x = (p0.x - p1.x) * workW;
          final v1y = (p0.y - p1.y) * workH;
          final v2x = (p2.x - p1.x) * workW;
          final v2y = (p2.y - p1.y) * workH;
          final len1 = math.sqrt(v1x * v1x + v1y * v1y);
          final len2 = math.sqrt(v2x * v2x + v2y * v2y);
          if (len1 < 1e-4 || len2 < 1e-4) continue;
          final cosA = (v1x * v2x + v1y * v2y) / (len1 * len2);
          final angleDeg = math.acos(cosA.clamp(-1.0, 1.0)) * 180.0 / math.pi;
          final dev = (angleDeg - 90.0).abs();
          totalAngleDev += dev;
          if (dev > maxAngleDev) maxAngleDev = dev;
        }
        if (maxAngleDev > 35.0) continue;
        final avgAngleDev = totalAngleDev / 4.0;

        // Brightness contrast: interior vs exterior
        final contrast = _evaluateBrightnessContrast(luma, candidateQuad, workW, workH);

        final score = area * 70.0 + contrast * 1.5 - avgAngleDev * 1.0;
        if (score > bestScore) {
          bestScore = score;
          bestQuad = candidateQuad;
        }
      }
    }

    return bestQuad;
  }

  /// Floods background from padded image borders; unreached interior is document.
  static Uint8List _floodFillFromBorder(Uint8List barrier, int w, int h) {
    final pw = w + 2;
    final ph = h + 2;
    final totalPad = pw * ph;
    final grid = Uint8List(totalPad);

    for (var y = 0; y < h; y++) {
      final srcRow = y * w;
      final dstRow = (y + 1) * pw + 1;
      for (var x = 0; x < w; x++) {
        if (barrier[srcRow + x] > 0) {
          grid[dstRow + x] = 255; // Barrier wall
        }
      }
    }

    // BFS queue from (0,0)
    final queue = <int>[0];
    grid[0] = 128; // Visited background

    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      final cx = curr % pw;
      final cy = curr ~/ pw;

      const dx = [0, 1, 0, -1];
      const dy = [-1, 0, 1, 0];
      for (var i = 0; i < 4; i++) {
        final nx = cx + dx[i];
        final ny = cy + dy[i];
        if (nx >= 0 && nx < pw && ny >= 0 && ny < ph) {
          final nIdx = ny * pw + nx;
          if (grid[nIdx] == 0) {
            grid[nIdx] = 128;
            queue.add(nIdx);
          }
        }
      }
    }

    final interior = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final srcRow = (y + 1) * pw + 1;
      final dstRow = y * w;
      for (var x = 0; x < w; x++) {
        if (grid[srcRow + x] != 128) {
          interior[dstRow + x] = 255;
        }
      }
    }
    return interior;
  }

  static Uint8List _gaussianBlur5x5(Uint8List gray, int width, int height) {
    final out = Uint8List(width * height);
    const kernel = [
      1, 4, 7, 4, 1,
      4, 16, 26, 16, 4,
      7, 26, 41, 26, 7,
      4, 16, 26, 16, 4,
      1, 4, 7, 4, 1,
    ];
    const kSum = 273;

    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        var sum = 0;
        var kIdx = 0;
        for (var ky = -2; ky <= 2; ky++) {
          final sy = (y + ky).clamp(0, height - 1);
          final sRow = sy * width;
          for (var kx = -2; kx <= 2; kx++) {
            final sx = (x + kx).clamp(0, width - 1);
            sum += gray[sRow + sx] * kernel[kIdx++];
          }
        }
        out[row + x] = (sum ~/ kSum).clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List _computeCanny(
    Uint8List gray,
    int width,
    int height, {
    double low = 20,
    double high = 60,
  }) {
    final size = width * height;
    final gx = Float32List(size);
    final gy = Float32List(size);
    final mag = Float32List(size);

    for (var y = 1; y < height - 1; y++) {
      final yPrev = (y - 1) * width;
      final yCurr = y * width;
      final yNext = (y + 1) * width;
      for (var x = 1; x < width - 1; x++) {
        final xGrad = -gray[yPrev + x - 1] + gray[yPrev + x + 1]
            - 2 * gray[yCurr + x - 1] + 2 * gray[yCurr + x + 1]
            - gray[yNext + x - 1] + gray[yNext + x + 1];
        final yGrad = -gray[yPrev + x - 1] - 2 * gray[yPrev + x] - gray[yPrev + x + 1]
            + gray[yNext + x - 1] + 2 * gray[yNext + x] + gray[yNext + x + 1];
        final idx = yCurr + x;
        gx[idx] = xGrad.toDouble();
        gy[idx] = yGrad.toDouble();
        mag[idx] = math.sqrt(xGrad * xGrad + yGrad * yGrad);
      }
    }

    final nms = Float32List(size);
    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      for (var x = 1; x < width - 1; x++) {
        final idx = row + x;
        final m = mag[idx];
        if (m < low) continue;

        final vx = gx[idx];
        final vy = gy[idx];
        var angle = math.atan2(vy, vx) * 180.0 / math.pi;
        if (angle < 0) angle += 180;

        double m1 = 0.0, m2 = 0.0;
        if ((angle >= 0 && angle < 22.5) || (angle >= 157.5 && angle <= 180)) {
          m1 = mag[idx - 1];
          m2 = mag[idx + 1];
        } else if (angle >= 22.5 && angle < 67.5) {
          m1 = mag[idx - width + 1];
          m2 = mag[idx + width - 1];
        } else if (angle >= 67.5 && angle < 112.5) {
          m1 = mag[idx - width];
          m2 = mag[idx + width];
        } else {
          m1 = mag[idx - width - 1];
          m2 = mag[idx + width + 1];
        }

        if (m >= m1 && m >= m2) {
          nms[idx] = m;
        }
      }
    }

    final out = Uint8List(size);
    final stack = <int>[];
    for (var i = 0; i < size; i++) {
      if (nms[i] >= high) {
        out[i] = 255;
        stack.add(i);
      }
    }

    while (stack.isNotEmpty) {
      final curr = stack.removeLast();
      final cx = curr % width;
      final cy = curr ~/ width;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = cy + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = cx + dx;
          if (nx < 0 || nx >= width) continue;
          final nIdx = ny * width + nx;
          if (out[nIdx] == 0 && nms[nIdx] >= low) {
            out[nIdx] = 255;
            stack.add(nIdx);
          }
        }
      }
    }
    return out;
  }

  static Uint8List _morphClose(Uint8List src, int w, int h, int k) {
    final rad = k ~/ 2;
    final dilated = Uint8List(w * h);
    final closed = Uint8List(w * h);

    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - rad);
      final y1 = math.min(h - 1, y + rad);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - rad);
        final x1 = math.min(w - 1, x + rad);
        var hit = false;
        for (var cy = y0; cy <= y1 && !hit; cy++) {
          final row = cy * w;
          for (var cx = x0; cx <= x1; cx++) {
            if (src[row + cx] > 0) {
              hit = true;
              break;
            }
          }
        }
        if (hit) dilated[y * w + x] = 255;
      }
    }

    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - rad);
      final y1 = math.min(h - 1, y + rad);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - rad);
        final x1 = math.min(w - 1, x + rad);
        var all = true;
        for (var cy = y0; cy <= y1 && all; cy++) {
          final row = cy * w;
          for (var cx = x0; cx <= x1; cx++) {
            if (dilated[row + cx] == 0) {
              all = false;
              break;
            }
          }
        }
        if (all) closed[y * w + x] = 255;
      }
    }
    return closed;
  }

  static Uint8List _keepLargestConnectedComponent(Uint8List bin, int w, int h) {
    final visited = Uint8List(w * h);
    var maxCount = 0;
    var bestLabel = 0;
    var currentLabel = 0;

    final labels = Int32List(w * h);

    for (var y = 1; y < h - 1; y++) {
      final row = y * w;
      for (var x = 1; x < w - 1; x++) {
        final idx = row + x;
        if (bin[idx] == 0 || visited[idx] != 0) continue;

        currentLabel++;
        var count = 0;
        final queue = <int>[idx];
        visited[idx] = 1;
        labels[idx] = currentLabel;

        while (queue.isNotEmpty) {
          final curr = queue.removeLast();
          count++;
          final cx = curr % w;
          final cy = curr ~/ w;

          for (var dy = -1; dy <= 1; dy++) {
            final ny = cy + dy;
            if (ny < 0 || ny >= h) continue;
            final nRow = ny * w;
            for (var dx = -1; dx <= 1; dx++) {
              final nx = cx + dx;
              if (nx < 0 || nx >= w) continue;
              final nIdx = nRow + nx;
              if (bin[nIdx] > 0 && visited[nIdx] == 0) {
                visited[nIdx] = 1;
                labels[nIdx] = currentLabel;
                queue.add(nIdx);
              }
            }
          }
        }

        if (count > maxCount) {
          maxCount = count;
          bestLabel = currentLabel;
        }
      }
    }

    final out = Uint8List(w * h);
    if (bestLabel == 0) return out;
    for (var i = 0; i < w * h; i++) {
      if (labels[i] == bestLabel) {
        out[i] = 255;
      }
    }
    return out;
  }

  static List<_Pt> _extractBoundaryPoints(Uint8List bin, int w, int h) {
    final points = <_Pt>[];
    const step = 2;
    for (var y = 1; y < h - 1; y += step) {
      final row = y * w;
      for (var x = 1; x < w - 1; x += step) {
        if (bin[row + x] > 0) {
          if (bin[row - w + x] == 0 ||
              bin[row + w + x] == 0 ||
              bin[row + x - 1] == 0 ||
              bin[row + x + 1] == 0) {
            points.add(_Pt(x.toDouble(), y.toDouble()));
          }
        }
      }
    }
    return points;
  }

  static double _polygonPerimeter(List<_Pt> poly) {
    var p = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final next = poly[(i + 1) % poly.length];
      final dx = poly[i].x - next.x;
      final dy = poly[i].y - next.y;
      p += math.sqrt(dx * dx + dy * dy);
    }
    return p;
  }

  static List<_Pt> _approxPolyRDP(List<_Pt> points, double epsilon) {
    if (points.length <= 4) return points;

    // Find two points on the polygon farthest apart
    var maxDistSq = 0.0;
    var idx1 = 0;
    var idx2 = points.length ~/ 2;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dx = points[i].x - points[j].x;
        final dy = points[i].y - points[j].y;
        final d2 = dx * dx + dy * dy;
        if (d2 > maxDistSq) {
          maxDistSq = d2;
          idx1 = i;
          idx2 = j;
        }
      }
    }

    if (idx1 > idx2) {
      final t = idx1;
      idx1 = idx2;
      idx2 = t;
    }

    // Split into 2 open polygonal chains: idx1 -> idx2, and idx2 -> idx1
    final chain1 = points.sublist(idx1, idx2 + 1);
    final chain2 = [...points.sublist(idx2), ...points.sublist(0, idx1 + 1)];

    final r1 = _rdpRecursive(chain1, 0, chain1.length - 1, epsilon);
    final r2 = _rdpRecursive(chain2, 0, chain2.length - 1, epsilon);

    final combined = [
      ...r1.take(r1.length - 1),
      ...r2.take(r2.length - 1),
    ];
    return combined;
  }

  static List<_Pt> _rdpRecursive(List<_Pt> pts, int start, int end, double eps) {
    var maxDist = 0.0;
    var index = 0;
    final a = pts[start];
    final b = pts[end];

    for (var i = start + 1; i < end; i++) {
      final dist = _perpendicularDistance(pts[i], a, b);
      if (dist > maxDist) {
        maxDist = dist;
        index = i;
      }
    }

    if (maxDist > eps) {
      final r1 = _rdpRecursive(pts, start, index, eps);
      final r2 = _rdpRecursive(pts, index, end, eps);
      return [...r1.take(r1.length - 1), ...r2];
    } else {
      return [a, b];
    }
  }

  static double _perpendicularDistance(_Pt p, _Pt a, _Pt b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return math.sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y));
    return ((dy * p.x - dx * p.y + b.x * a.y - b.y * a.x).abs()) / len;
  }

  static bool _isConvex(List<_Pt> pts) {
    if (pts.length < 3) return false;
    var sign = 0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final c = pts[(i + 2) % pts.length];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() > 1e-4) {
        final currSign = cross > 0 ? 1 : -1;
        if (sign == 0) {
          sign = currSign;
        } else if (sign != currSign) {
          return false;
        }
      }
    }
    return true;
  }

  static List<_Pt> _minAreaRectCorners(List<_Pt> hull) {
    if (hull.length < 3) return _extremeCorners(hull);
    var minArea = 1e12;
    List<_Pt> bestBox = [];

    // Rotating calipers: test each edge direction of the hull
    for (var i = 0; i < hull.length; i++) {
      final p1 = hull[i];
      final p2 = hull[(i + 1) % hull.length];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;

      final ux = dx / len;
      final uy = dy / len;
      final vx = -uy;
      final vy = ux;

      var minU = 1e9, maxU = -1e9;
      var minV = 1e9, maxV = -1e9;

      for (final p in hull) {
        final u = p.x * ux + p.y * uy;
        final v = p.x * vx + p.y * vy;
        if (u < minU) minU = u;
        if (u > maxU) maxU = u;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }

      final area = (maxU - minU) * (maxV - minV);
      if (area < minArea && area > 0) {
        minArea = area;
        bestBox = [
          _Pt(minU * ux + minV * vx, minU * uy + minV * vy),
          _Pt(maxU * ux + minV * vx, maxU * uy + minV * vy),
          _Pt(maxU * ux + maxV * vx, maxU * uy + maxV * vy),
          _Pt(minU * ux + maxV * vx, minU * uy + maxV * vy),
        ];
      }
    }

    return bestBox.length == 4 ? bestBox : _extremeCorners(hull);
  }

  static List<_Pt> _extremeCorners(List<_Pt> hull) {
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

  static List<_Pt> _convexHull(List<_Pt> points) {
    final sorted = [...points]
      ..sort((a, b) {
        final byX = a.x.compareTo(b.x);
        return byX != 0 ? byX : a.y.compareTo(b.y);
      });
    final unique = <_Pt>[];
    for (final point in sorted) {
      if (unique.isEmpty || unique.last.x != point.x || unique.last.y != point.y) {
        unique.add(point);
      }
    }
    if (unique.length <= 3) return unique;

    double cross(_Pt o, _Pt a, _Pt b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

    final lower = <_Pt>[];
    for (final point in unique) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <_Pt>[];
    for (final point in unique.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static double _evaluateBrightnessContrast(Uint8List luma, Quad quad, int w, int h) {
    var insideSum = 0;
    var insideCount = 0;
    final tl = quad.topLeft;
    final tr = quad.topRight;
    final br = quad.bottomRight;
    final bl = quad.bottomLeft;

    // Bilinear sampling strictly inside the quad
    for (var u = 0.2; u <= 0.8; u += 0.2) {
      for (var v = 0.2; v <= 0.8; v += 0.2) {
        final topX = tl.x + (tr.x - tl.x) * u;
        final topY = tl.y + (tr.y - tl.y) * u;
        final botX = bl.x + (br.x - bl.x) * u;
        final botY = bl.y + (br.y - bl.y) * u;
        final px = ((topX + (botX - topX) * v) * (w - 1)).round().clamp(0, w - 1);
        final py = ((topY + (botY - topY) * v) * (h - 1)).round().clamp(0, h - 1);
        insideSum += luma[py * w + px];
        insideCount++;
      }
    }

    var outSum = 0;
    var outCount = 0;
    final testOut = [
      (0, 0),
      (w - 1, 0),
      (0, h - 1),
      (w - 1, h - 1),
      (w ~/ 2, 0),
      (w ~/ 2, h - 1),
      (0, h ~/ 2),
      (w - 1, h ~/ 2),
    ];
    for (final pos in testOut) {
      outSum += luma[pos.$2 * w + pos.$1];
      outCount++;
    }

    final insideMean = insideCount > 0 ? insideSum / insideCount : 128.0;
    final outMean = outCount > 0 ? outSum / outCount : 128.0;
    return insideMean - outMean;
  }
}

class _Pt {
  const _Pt(this.x, this.y);
  final double x;
  final double y;
}
