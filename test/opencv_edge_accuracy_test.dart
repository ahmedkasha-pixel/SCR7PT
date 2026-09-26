// Accuracy check for the OpenCV edge detector on real photos.
//
// The photos are private and are never committed. Point the test at a local
// folder that holds photo1.jpg .. photo4.jpg:
//
//   SCR7PT_REAL_PHOTOS=/path/to/photos flutter test test/opencv_edge_accuracy_test.dart
//
// Without the variable the test is skipped. The ground truth and the metric
// (polygon IoU in the 576x1024 frame) are the Python prototype's.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/frame_quad.dart';
import 'package:docscan/core/processing/opencv_edge_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'support/polygon_iou.dart';
import 'support/yuv_frames.dart';

const _gt = <String, List<double>>{
  'photo1': [30, 170, 515, 180, 525, 855, 35, 860],
  'photo2': [55, 100, 510, 95, 540, 738, 82, 742],
  'photo3': [22, 100, 576, 75, 576, 890, 18, 870],
  'photo4': [22, 90, 516, 72, 528, 760, 38, 773],
};

/// IoU measured by the Python prototype (unified_detector.py).
const _pythonIoU = <String, double>{
  'photo1': 0.9624,
  'photo2': 0.9694,
  'photo3': 0.9791,
  'photo4': 0.9590,
};

void main() {
  final dir = Platform.environment['SCR7PT_REAL_PHOTOS'];
  final skip = dir == null || dir.isEmpty
      ? 'Set SCR7PT_REAL_PHOTOS to a folder with photo1..4.jpg (private, not in git).'
      : null;

  group('OpenCV detector on real photos', () {
    for (final name in _gt.keys) {
      test('$name matches the Python prototype', () {
        final path = '$dir/$name.jpg';
        expect(File(path).existsSync(), isTrue, reason: 'missing $path');
        final gt = _gt[name]!;

        // 1. Prototype harness: imread + INTER_AREA resize to 576x1024.
        final full = cv.imread(path);
        final frame = cv.resize(full, (576, 1024), interpolation: cv.INTER_AREA);
        final sw = Stopwatch()..start();
        final pts = OpenCvEdgeDetector.detectPixelQuad(frame);
        sw.stop();
        full.dispose();
        frame.dispose();
        expect(pts, isNotNull, reason: 'no quad on $name');
        final iou = polygonIoU(gt, [for (final v in pts!) v.toDouble()]);

        // 2. App path: package:image decode -> OpenCvEdgeDetector.detect.
        final decoded = img.decodeImage(File(path).readAsBytesSync())!;
        final sw2 = Stopwatch()..start();
        final quad = OpenCvEdgeDetector.detect(decoded);
        sw2.stop();
        expect(quad, isNotNull, reason: 'app path found no quad on $name');
        final appIoU = polygonIoU(gt, _toFrame(quad!, 576, 1024));

        // 3. Live preview path: the photo as a 1280x720 landscape YUV420
        //    sensor frame (orientation 90), rotated and detected at 512 px.
        final sensor = img.copyResize(
          img.copyRotate(decoded, angle: 270),
          width: 1280,
          height: 720,
          interpolation: img.Interpolation.average,
        );
        final sw3 = Stopwatch()..start();
        final live = detectFrameQuad(yuvFrameFrom(sensor, sensorOrientation: 90));
        sw3.stop();
        expect(live, isNotNull, reason: 'live path found no quad on $name');
        final liveIoU = polygonIoU(gt, _toFrame(live!, 576, 1024));

        final py = _pythonIoU[name]!;
        print('$name: python ${(py * 100).toStringAsFixed(2)}% | '
            'dart ${(iou * 100).toStringAsFixed(2)}% (${sw.elapsedMilliseconds} ms) | '
            'app path ${(appIoU * 100).toStringAsFixed(2)}% (${sw2.elapsedMilliseconds} ms) | '
            'live frame ${(liveIoU * 100).toStringAsFixed(2)}% (${sw3.elapsedMilliseconds} ms)');
        print('  dart quad: ${pts.map((v) => v.toStringAsFixed(1)).join(', ')}');

        expect(iou, greaterThanOrEqualTo(0.90));
        expect((iou - py).abs(), lessThanOrEqualTo(0.01),
            reason: 'Dart port drifts from Python on $name');
        expect(appIoU, greaterThanOrEqualTo(0.90));
        expect(liveIoU, greaterThanOrEqualTo(0.90));
      });
    }
  }, skip: skip);
}

List<double> _toFrame(Quad q, int w, int h) => [
  for (final p in q.points) ...[p.x * (w - 1), p.y * (h - 1)],
];
