import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../geometry/quad.dart';

/// OpenCV document-edge detector, ported from the Python prototype
/// `unified_detector.py` (`detect_document_quad`).
///
/// Pipeline (same order and parameters as the prototype):
/// 1. Gray and HSV saturation, 5x5 Gaussian blur, Canny 25/75 on both,
///    combined edge map, plus a paper mask (sat < 50 and val > 95).
/// 2. Candidates:
///    A. RETR_EXTERNAL contours of the edge map closed with 9/15 px kernels
///       and of the paper mask closed with 7/13 px kernels, approxPolyDP at
///       1.5/2.5/3.5/5 % of the perimeter, convex 4-gons with 15-95 % area.
///    B. HoughLinesP boundary lines split into top/bottom/left/right, scored
///       by inside/outside luma and saturation contrast; the top five of each
///       side are intersected (with a right-frame-edge fallback for pages that
///       run off the right border).
/// 3. Every candidate is scored by luma/saturation contrast, Canny edge
///    alignment along a 12 px band, area, angle regularity, A4 aspect and a
///    dark-frame-border penalty; the best one wins.
///
/// The prototype's pixel thresholds (kernel sizes, 8 px border strips, the
/// 12 px band, 5/10 px border tests) were tuned on frames whose long edge is
/// 1024 px, so [detect] first resizes every input to that long edge and then
/// runs the prototype unchanged. On a 576x1024 frame this is exactly the
/// prototype.
///
/// The scoring stage is computed with bounding-box ROIs and pre-computed
/// image sums instead of full-frame masks; the numbers are the same as the
/// prototype's full-frame `cv2.mean`/`countNonZero` calls, only faster.
class OpenCvEdgeDetector {
  const OpenCvEdgeDetector._();

  /// Long edge the prototype was tuned for (capture and import).
  static const int workingLongEdge = 1024;

  /// Long edge used for live camera frames. The prototype's own `scale`
  /// logic handles smaller frames (edges and lines are still found at 1024,
  /// scoring runs at 640), which roughly halves the cost per preview frame.
  /// On the four reference photos fed as 640x360, 1280x720 and 1920x1080
  /// YUV frames it stayed at 94-99 % IoU; 512 dropped one photo to ~89 %.
  static const int liveLongEdge = 640;

  /// Detects the page in an RGB [source] and returns normalized corners, or
  /// null when no candidate passes the prototype's filters.
  ///
  /// Throws if the native OpenCV library cannot be loaded; callers fall back
  /// to the pure-Dart detector in that case.
  static Quad? detect(img.Image source) {
    final rgb = source.format == img.Format.uint8 && source.numChannels == 3
        ? source
        : source.convert(format: img.Format.uint8, numChannels: 3);
    return detectRgbBytes(rgb.toUint8List(), rgb.width, rgb.height);
  }

  /// Same as [detect] for packed 8-bit RGB bytes (`width * height * 3`).
  static Quad? detectRgbBytes(Uint8List rgb, int width, int height) {
    if (width < 8 || height < 8) return null;
    final rgbMat = cv.Mat.zeros(height, width, cv.MatType.CV_8UC3);
    try {
      rgbMat.data.setAll(0, rgb);
      final bgr = cv.cvtColor(rgbMat, cv.COLOR_RGB2BGR);
      try {
        return detectBgrMat(bgr);
      } finally {
        bgr.dispose();
      }
    } finally {
      rgbMat.dispose();
    }
  }

  /// Detects on a BGR [cv.Mat] of any size. The frame is resized to
  /// [longEdge] (default [workingLongEdge]) first; the result is normalized
  /// to 0..1.
  static Quad? detectBgrMat(cv.Mat bgr, {int longEdge = workingLongEdge}) {
    final h = bgr.rows;
    final w = bgr.cols;
    if (w < 8 || h < 8) return null;
    final scale = longEdge / math.max(w, h);
    final nw = math.max(1, (w * scale).round());
    final nh = math.max(1, (h * scale).round());
    final cv.Mat frame;
    if (nw == w && nh == h) {
      frame = bgr;
    } else {
      frame = cv.resize(
        bgr,
        (nw, nh),
        interpolation: scale < 1 ? cv.INTER_AREA : cv.INTER_LINEAR,
      );
    }
    try {
      final pts = detectPixelQuad(frame);
      if (pts == null) return null;
      final sx = nw > 1 ? nw - 1 : 1;
      final sy = nh > 1 ? nh - 1 : 1;
      return Quad(
        topLeft: NormPoint(_unit(pts[0] / sx), _unit(pts[1] / sy)),
        topRight: NormPoint(_unit(pts[2] / sx), _unit(pts[3] / sy)),
        bottomRight: NormPoint(_unit(pts[4] / sx), _unit(pts[5] / sy)),
        bottomLeft: NormPoint(_unit(pts[6] / sx), _unit(pts[7] / sy)),
      );
    } finally {
      if (!identical(frame, bgr)) frame.dispose();
    }
  }

  static double _unit(double v) => v.clamp(0.0, 1.0).toDouble();

  /// Faithful port of `detect_document_quad(img)`: returns the corners in
  /// pixel coordinates of [image] (TL, TR, BR, BL as x0,y0,...,x3,y3), or
  /// null when nothing qualifies.
  static Float32List? detectPixelQuad(cv.Mat image) {
    final h = image.rows;
    final w = image.cols;
    final scale = 1024.0 / math.max(h, w);
    final nw = _pyRound(w * scale);
    final nh = _pyRound(h * scale);
    final disposables = <cv.Mat>[];
    cv.Mat keep(cv.Mat m) {
      disposables.add(m);
      return m;
    }

    try {
      final work = keep(
        cv.resize(image, (nw, nh), interpolation: cv.INTER_AREA),
      );
      final grayMat = keep(cv.cvtColor(work, cv.COLOR_BGR2GRAY));
      final hsvMat = keep(cv.cvtColor(work, cv.COLOR_BGR2HSV));
      final satMat = keep(cv.extractChannel(hsvMat, 1));
      final valMat = keep(cv.extractChannel(hsvMat, 2));

      final blurredG = keep(cv.gaussianBlur(grayMat, (5, 5), 0));
      final blurredS = keep(cv.gaussianBlur(satMat, (5, 5), 0));
      final eg = keep(cv.canny(blurredG, 25, 75));
      final es = keep(cv.canny(blurredS, 25, 75));
      final combEdges = keep(cv.max(eg, es));

      final gray = Uint8List.fromList(grayMat.data);
      final sat = Uint8List.fromList(satMat.data);
      final val = valMat.data;

      final candidates = <Float32List>[];

      // ---------------------------------------------------------------
      // Strategy A: contours on the closed edge map and paper mask.
      // ---------------------------------------------------------------
      final satMaskMat = keep(cv.Mat.zeros(nh, nw, cv.MatType.CV_8UC1));
      final satMaskData = satMaskMat.data;
      for (var i = 0; i < nw * nh; i++) {
        if (sat[i] < 50 && val[i] > 95) satMaskData[i] = 255;
      }

      final borderValue = cv.morphologyDefaultBorderValue();
      final minContourArea = nw * nh * 0.15;
      final maxContourArea = nw * nh * 0.95;
      for (final (src, kSizes) in [
        (combEdges, const [9, 15]),
        (satMaskMat, const [7, 13]),
      ]) {
        for (final k in kSizes) {
          final kernel = cv.getStructuringElement(cv.MORPH_RECT, (k, k));
          final closed = cv.morphologyEx(
            src,
            cv.MORPH_CLOSE,
            kernel,
            borderType: cv.BORDER_CONSTANT,
            borderValue: borderValue,
          );
          final (contours, hierarchy) = cv.findContours(
            closed,
            cv.RETR_EXTERNAL,
            cv.CHAIN_APPROX_SIMPLE,
          );
          for (final cnt in contours) {
            final area = cv.contourArea(cnt);
            if (area < minContourArea || area > maxContourArea) continue;
            final peri = cv.arcLength(cnt, true);
            for (final epsF in const [0.015, 0.025, 0.035, 0.05]) {
              final approx = cv.approxPolyDP(cnt, epsF * peri, true);
              if (approx.length == 4 && cv.isContourConvex(approx)) {
                final raw = Float64List(8);
                for (var i = 0; i < 4; i++) {
                  final p = approx[i];
                  raw[i * 2] = p.x / scale;
                  raw[i * 2 + 1] = p.y / scale;
                }
                candidates.add(_orderPoints(raw));
              }
              approx.dispose();
            }
          }
          contours.dispose();
          hierarchy.dispose();
          closed.dispose();
          kernel.dispose();
        }
      }

      // ---------------------------------------------------------------
      // Strategy B: directed boundary Hough lines.
      // ---------------------------------------------------------------
      final linesMat = keep(
        cv.HoughLinesP(
          combEdges,
          1,
          math.pi / 180,
          35,
          minLineLength: (30 * scale).truncateToDouble(),
          maxLineGap: (15 * scale).truncateToDouble(),
        ),
      );
      final lineCount = linesMat.isEmpty ? 0 : linesMat.rows * linesMat.cols;
      if (lineCount > 0) {
        final lineData = Int32List.fromList(
          linesMat.data.buffer.asInt32List(
            linesMat.data.offsetInBytes,
            lineCount * 4,
          ),
        );

        double lineScore(int x1, int y1, int x2, int y2, bool isHoriz, int side) {
          final length = _hypot((x2 - x1).toDouble(), (y2 - y1).toDouble());
          if (length < 25 * scale) return -1e5;
          final d = math.max(3, (8 * scale).truncate());
          var inS = 0.0, outS = 0.0, inL = 0.0, outL = 0.0;
          for (var s = 0; s < 10; s++) {
            final u = 0.1 + s * ((0.9 - 0.1) / 9);
            final cx = x1 + u * (x2 - x1);
            final cy = y1 + u * (y2 - y1);
            int iIn, iOut;
            if (isHoriz) {
              final nyIn = _clip(cy + side * d, 0, nh - 1).truncate();
              final nyOut = _clip(cy - side * d, 0, nh - 1).truncate();
              final nx = _clip(cx, 0, nw - 1).truncate();
              iIn = nyIn * nw + nx;
              iOut = nyOut * nw + nx;
            } else {
              final nxIn = _clip(cx + side * d, 0, nw - 1).truncate();
              final nxOut = _clip(cx - side * d, 0, nw - 1).truncate();
              final ny = _clip(cy, 0, nh - 1).truncate();
              iIn = ny * nw + nxIn;
              iOut = ny * nw + nxOut;
            }
            inL += gray[iIn];
            outL += gray[iOut];
            inS += sat[iIn];
            outS += sat[iOut];
          }
          inS /= 10;
          outS /= 10;
          inL /= 10;
          outL /= 10;
          final sDiff = outS - inS;
          final lDiff = inL - outL;
          final penalty =
              math.max(0.0, inS - 35) * 2.5 + math.max(0.0, 105 - inL) * 2.0;
          return (sDiff * 1.5 + lDiff * 1.0 - penalty) * math.log(length + 1);
        }

        final tCands = <_Line>[];
        final bCands = <_Line>[];
        final lCands = <_Line>[];
        final rCands = <_Line>[];
        for (var i = 0; i < lineCount; i++) {
          final x1 = lineData[i * 4];
          final y1 = lineData[i * 4 + 1];
          final x2 = lineData[i * 4 + 2];
          final y2 = lineData[i * 4 + 3];
          final dx = x2 - x1;
          final dy = y2 - y1;
          final angle = (math.atan2(dy, dx) * 180 / math.pi).abs();
          _Line mk(double sc, int order) => _Line(
            x1 / scale,
            y1 / scale,
            x2 / scale,
            y2 / scale,
            sc,
            order,
          );
          if (angle < 14 || angle > 166) {
            final my = (y1 + y2) / 2;
            if (my < 0.45 * nh) {
              final sc = lineScore(x1, y1, x2, y2, true, 1);
              if (sc > 0) tCands.add(mk(sc, i));
            }
            if (my > 0.55 * nh) {
              final sc = lineScore(x1, y1, x2, y2, true, -1);
              if (sc > 0) bCands.add(mk(sc, i));
            }
          } else if (angle > 75 && angle < 105) {
            final mx = (x1 + x2) / 2;
            if (mx < 0.45 * nw) {
              final sc = lineScore(x1, y1, x2, y2, false, 1);
              if (sc > 0) lCands.add(mk(sc, i));
            }
            if (mx > 0.55 * nw) {
              final sc = lineScore(x1, y1, x2, y2, false, -1);
              if (sc > 0) rCands.add(mk(sc, i));
            }
          }
        }
        // Python's sort is stable; keep insertion order on equal scores.
        int byScore(_Line a, _Line b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : a.order.compareTo(b.order);
        }

        tCands.sort(byScore);
        bCands.sort(byScore);
        lCands.sort(byScore);
        rCands.sort(byScore);

        // Right frame boundary fallback (page running off the right edge).
        final r0 = (0.2 * nh).truncate();
        final r1 = (0.8 * nh).truncate();
        final cw = (10 * scale).truncate();
        var rightSum = 0.0;
        var rightCount = 0;
        for (var y = r0; y < r1; y++) {
          for (var x = nw - cw; x < nw; x++) {
            rightSum += sat[y * nw + x];
            rightCount++;
          }
        }
        final rightSat = rightCount > 0 ? rightSum / rightCount : double.nan;
        var rList = rCands.take(5).toList();
        if (rightSat < 30 || rList.isEmpty) {
          rList = [
            _Line(
              (w - 1).toDouble(),
              0,
              (w - 1).toDouble(),
              (h - 1).toDouble(),
              1000,
              -1,
            ),
            ...rList,
          ];
        }
        final tList = tCands.take(5).toList();
        final bList = bCands.take(5).toList();
        final lList = lCands.take(5).toList();

        final raw = Float64List(8);
        for (final t in tList) {
          final lt = t.homogeneous;
          for (final b in bList) {
            final lb = b.homogeneous;
            for (final l in lList) {
              final ll = l.homogeneous;
              for (final r in rList) {
                final lr = r.homogeneous;
                if (!_intersect(lt, ll, raw, 0) ||
                    !_intersect(lt, lr, raw, 1) ||
                    !_intersect(lb, lr, raw, 2) ||
                    !_intersect(lb, ll, raw, 3)) {
                  continue;
                }
                var outside = false;
                for (var i = 0; i < 4; i++) {
                  final x = raw[i * 2];
                  final y = raw[i * 2 + 1];
                  if (x < -4 || y < -4 || x > w + 4 || y > h + 4) {
                    outside = true;
                    break;
                  }
                }
                if (outside) continue;
                for (var i = 0; i < 4; i++) {
                  raw[i * 2] = _f32(_clip(raw[i * 2], 0, w - 1));
                  raw[i * 2 + 1] = _f32(_clip(raw[i * 2 + 1], 0, h - 1));
                }
                candidates.add(_orderPoints(raw));
              }
            }
          }
        }
      }

      if (candidates.isEmpty) return null;
      return _selectBest(image, candidates, disposables);
    } finally {
      for (final m in disposables) {
        m.dispose();
      }
    }
  }

  /// Candidate scoring and selection (the prototype's objective function).
  static Float32List? _selectBest(
    cv.Mat image,
    List<Float32List> candidates,
    List<cv.Mat> disposables,
  ) {
    final h = image.rows;
    final w = image.cols;
    final fullGrayMat = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    disposables.add(fullGrayMat);
    final fullHsv = cv.cvtColor(image, cv.COLOR_BGR2HSV);
    disposables.add(fullHsv);
    final fullSatMat = cv.extractChannel(fullHsv, 1);
    disposables.add(fullSatMat);
    final fullEdges = cv.canny(fullGrayMat, 30, 90);
    disposables.add(fullEdges);

    final fullGray = fullGrayMat.data;
    final fullSat = fullSatMat.data;
    final total = w * h;
    var graySum = 0.0;
    var satSum = 0.0;
    for (var i = 0; i < total; i++) {
      graySum += fullGray[i];
      satSum += fullSat[i];
    }

    double stripMean(int x0, int x1, int y0, int y1) {
      var s = 0.0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          s += fullGray[y * w + x];
          n++;
        }
      }
      return n > 0 ? s / n : double.nan;
    }

    final topDark = stripMean((0.2 * w).truncate(), (0.8 * w).truncate(), 0,
            math.min(8, h)) <
        115;
    final leftDark = stripMean(0, math.min(8, w), (0.2 * h).truncate(),
            (0.8 * h).truncate()) <
        115;
    final bottomDark = stripMean((0.2 * w).truncate(), (0.8 * w).truncate(),
            math.max(0, h - 8), h) <
        115;
    final rightDark = stripMean(math.max(0, w - 8), w, (0.2 * h).truncate(),
            (0.8 * h).truncate()) <
        115;

    final white = cv.Scalar.all(255);
    var bestScore = -1e9;
    Float32List? best;
    final seen = <String>{};

    for (final pts in candidates) {
      // Identical candidates score identically and the first one wins ties,
      // so skipping repeats does not change the result.
      if (!seen.add(pts.join(','))) continue;

      var maxAngleDev = 0.0;
      var angleDevSum = 0.0;
      for (var i = 0; i < 4; i++) {
        final i0 = (i + 3) % 4;
        final i2 = (i + 1) % 4;
        final v1x = pts[i0 * 2] - pts[i * 2];
        final v1y = pts[i0 * 2 + 1] - pts[i * 2 + 1];
        final v2x = pts[i2 * 2] - pts[i * 2];
        final v2y = pts[i2 * 2 + 1] - pts[i * 2 + 1];
        final denom = _hypot(v1x, v1y) * _hypot(v2x, v2y);
        if (denom < 1e-5) {
          maxAngleDev = 100;
          break;
        }
        final cosA = ((v1x * v2x + v1y * v2y) / denom).clamp(-1.0, 1.0);
        final ang = math.acos(cosA) * 180 / math.pi;
        final dev = (ang - 90).abs();
        angleDevSum += dev;
        if (dev > maxAngleDev) maxAngleDev = dev;
      }
      if (maxAngleDev > 40) continue;

      // Integer polygon exactly as `pts.astype(np.int32)`.
      final ix = List<int>.generate(4, (i) => pts[i * 2].truncate());
      final iy = List<int>.generate(4, (i) => pts[i * 2 + 1].truncate());

      // Interior mask restricted to the polygon's bounding box.
      final bx0 = _clampInt(ix.reduce(math.min), 0, w - 1);
      final by0 = _clampInt(iy.reduce(math.min), 0, h - 1);
      final bx1 = _clampInt(ix.reduce(math.max), 0, w - 1);
      final by1 = _clampInt(iy.reduce(math.max), 0, h - 1);
      final rw = bx1 - bx0 + 1;
      final rh = by1 - by0 + 1;
      final mask = cv.Mat.zeros(rh, rw, cv.MatType.CV_8UC1);
      final poly = cv.VecVecPoint.fromList([
        [for (var i = 0; i < 4; i++) cv.Point(ix[i] - bx0, iy[i] - by0)],
      ]);
      cv.fillPoly(mask, poly, white);
      poly.dispose();
      final area = cv.countNonZero(mask);
      final areaRatio = area / total;
      if (areaRatio < 0.15 || areaRatio > 0.94) {
        mask.dispose();
        continue;
      }

      final minX = math.min(math.min(pts[0], pts[2]), math.min(pts[4], pts[6]));
      final maxX = math.max(math.max(pts[0], pts[2]), math.max(pts[4], pts[6]));
      final minY = math.min(math.min(pts[1], pts[3]), math.min(pts[5], pts[7]));
      final maxY = math.max(math.max(pts[1], pts[3]), math.max(pts[5], pts[7]));
      if (minX < 5 && maxX > w - 5 && minY < 5 && maxY > h - 5) {
        mask.dispose();
        continue;
      }

      final roi = cv.Rect(bx0, by0, rw, rh);
      final grayRoi = fullGrayMat.region(roi);
      final satRoi = fullSatMat.region(roi);
      final meanLumaIn = cv.mean(grayRoi, mask: mask).val1;
      final meanSatIn = cv.mean(satRoi, mask: mask).val1;
      grayRoi.dispose();
      satRoi.dispose();
      mask.dispose();
      final outCount = total - area;
      final meanLumaOut =
          outCount > 0 ? (graySum - meanLumaIn * area) / outCount : 0.0;
      final meanSatOut =
          outCount > 0 ? (satSum - meanSatIn * area) / outCount : 0.0;

      // Edge alignment on a 12 px band around the polygon.
      const pad = 8;
      final ex0 = _clampInt(ix.reduce(math.min) - pad, 0, w - 1);
      final ey0 = _clampInt(iy.reduce(math.min) - pad, 0, h - 1);
      final ex1 = _clampInt(ix.reduce(math.max) + pad, 0, w - 1);
      final ey1 = _clampInt(iy.reduce(math.max) + pad, 0, h - 1);
      final ew = ex1 - ex0 + 1;
      final eh = ey1 - ey0 + 1;
      final band = cv.Mat.zeros(eh, ew, cv.MatType.CV_8UC1);
      final bandPoly = cv.VecVecPoint.fromList([
        [for (var i = 0; i < 4; i++) cv.Point(ix[i] - ex0, iy[i] - ey0)],
      ]);
      cv.polylines(band, bandPoly, true, white, thickness: 12);
      bandPoly.dispose();
      final bandArea = cv.countNonZero(band);
      final edgeRoi = fullEdges.region(cv.Rect(ex0, ey0, ew, eh));
      final hits = cv.bitwiseAND(edgeRoi, band);
      final edgeAlignment = cv.countNonZero(hits) / (bandArea + 1e-5);
      hits.dispose();
      edgeRoi.dispose();
      band.dispose();

      final lumaContrast = meanLumaIn - meanLumaOut;
      final satContrast = meanSatOut - meanSatIn;
      final satInPenalty = math.max(0.0, meanSatIn - 20) * 4.0;

      final topW = _hypot(pts[2] - pts[0], pts[3] - pts[1]);
      final botW = _hypot(pts[4] - pts[6], pts[5] - pts[7]);
      final leftH = _hypot(pts[6] - pts[0], pts[7] - pts[1]);
      final rightH = _hypot(pts[4] - pts[2], pts[5] - pts[3]);
      final wAvg = (topW + botW) / 2;
      final hAvg = (leftH + rightH) / 2;
      final aspect = math.max(wAvg, hAvg) / (math.min(wAvg, hAvg) + 1e-5);
      final aspectDev = (aspect - 1.414).abs();

      var borderPenalty = 0.0;
      if (minY < 10 && topDark) borderPenalty += 150;
      if (minX < 10 && leftDark) borderPenalty += 150;
      if (maxY > h - 10 && bottomDark) borderPenalty += 150;
      if (maxX > w - 10 && rightDark) borderPenalty += 150;

      final score = lumaContrast * 1.5 +
          satContrast * 2.0 -
          satInPenalty +
          edgeAlignment * 600.0 +
          areaRatio * 40.0 -
          (angleDevSum / 4.0) * 1.5 -
          aspectDev * 80.0 -
          borderPenalty;

      if (score > bestScore) {
        bestScore = score;
        best = pts;
      }
    }
    return best;
  }

  /// `order_points`: TL = min(x+y), BR = max(x+y), TR = min(y-x),
  /// BL = max(y-x); first index wins ties like `np.argmin`/`np.argmax`.
  static Float32List _orderPoints(Float64List raw) {
    final p = Float32List(8);
    for (var i = 0; i < 8; i++) {
      p[i] = raw[i];
    }
    int pick(double Function(int i) f, bool minimum) {
      var idx = 0;
      var best = f(0);
      for (var i = 1; i < 4; i++) {
        final v = f(i);
        if (minimum ? v < best : v > best) {
          best = v;
          idx = i;
        }
      }
      return idx;
    }

    double sum(int i) => raw[i * 2] + raw[i * 2 + 1];
    double diff(int i) => raw[i * 2 + 1] - raw[i * 2];
    final order = [
      pick(sum, true),
      pick(diff, true),
      pick(sum, false),
      pick(diff, false),
    ];
    final out = Float32List(8);
    for (var k = 0; k < 4; k++) {
      out[k * 2] = p[order[k] * 2];
      out[k * 2 + 1] = p[order[k] * 2 + 1];
    }
    return out;
  }

  /// `intersect_lines`, result rounded to float32 like the prototype.
  static bool _intersect(Float64List l1, Float64List l2, Float64List out, int i) {
    final d = l1[0] * l2[1] - l1[1] * l2[0];
    if (d.abs() < 1e-6) return false;
    out[i * 2] = _f32((l1[1] * l2[2] - l1[2] * l2[1]) / d);
    out[i * 2 + 1] = _f32((l1[2] * l2[0] - l1[0] * l2[2]) / d);
    return true;
  }

  static final Float32List _f32Buf = Float32List(1);
  static double _f32(double v) {
    _f32Buf[0] = v;
    return _f32Buf[0];
  }

  static double _clip(double v, num lo, num hi) =>
      v < lo ? lo.toDouble() : (v > hi ? hi.toDouble() : v);

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  static double _hypot(double x, double y) => math.sqrt(x * x + y * y);

  /// Python 3 `round()` (half to even) for the working-size computation.
  static int _pyRound(double v) {
    final f = v.floorToDouble();
    final diff = v - f;
    if (diff > 0.5) return f.toInt() + 1;
    if (diff < 0.5) return f.toInt();
    return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
  }
}

class _Line {
  _Line(this.x1, this.y1, this.x2, this.y2, this.score, this.order)
    : homogeneous = Float64List.fromList([
        y2 - y1,
        x1 - x2,
        x2 * y1 - x1 * y2,
      ]);

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double score;
  final int order;

  /// `line_from_pts`: a*x + b*y + c = 0.
  final Float64List homogeneous;
}
