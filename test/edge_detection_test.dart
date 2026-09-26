import 'dart:math' as math;

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/document_processor.dart';
import 'package:docscan/core/processing/edge_detection.dart';
import 'package:docscan/core/processing/frame_quad.dart';
import 'package:docscan/core/processing/opencv_edge_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'support/polygon_iou.dart';
import 'support/yuv_frames.dart';

/// OpenCV's native library is built by the dartcv4 hook for the host. If it
/// is missing (for example a host without a C++ toolchain), the OpenCV tests
/// are skipped and only the fallback is checked.
String? _openCvSkip() {
  try {
    cv.Mat.zeros(2, 2, cv.MatType.CV_8UC1).dispose();
    return null;
  } catch (error) {
    return 'native OpenCV is not available on this host: $error';
  }
}

/// A white A4-ish page, slightly rotated, on a dark wood-like desk.
img.Image _desk(int w, int h, Quad page) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  final rnd = math.Random(7);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final grain = (18 * math.sin(y / 9.0 + x / 57.0)).round();
      final n = rnd.nextInt(10);
      image.setPixelRgb(x, y, 96 + grain + n, 62 + grain ~/ 2 + n, 38 + n);
    }
  }
  final pts = [
    for (final p in page.points) (p.x * (w - 1), p.y * (h - 1)),
  ];
  bool inside(double x, double y) {
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4];
      if ((b.$1 - a.$1) * (y - a.$2) - (b.$2 - a.$2) * (x - a.$1) < 0) {
        return false;
      }
    }
    return true;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (inside(x.toDouble(), y.toDouble())) {
        final n = rnd.nextInt(6);
        image.setPixelRgb(x, y, 236 + n, 234 + n, 228 + n);
      }
    }
  }
  return image;
}

const _page = Quad(
  topLeft: NormPoint(0.12, 0.14),
  topRight: NormPoint(0.86, 0.11),
  bottomRight: NormPoint(0.89, 0.86),
  bottomLeft: NormPoint(0.10, 0.88),
);

double _iou(Quad a, Quad b) => polygonIoU(a.toList(), b.toList());

void main() {
  final skip = _openCvSkip();
  tearDown(EdgeDetection.resetForTest);

  test('tryDetectQuad uses OpenCV and finds the page', () {
    final image = _desk(600, 800, _page);
    final quad = tryDetectQuad(image);
    expect(EdgeDetection.lastBackend, EdgeDetectorBackend.openCv);
    expect(quad, isNotNull);
    expect(_iou(quad!, _page), greaterThan(0.95));
  }, skip: skip);

  test('OpenCV result does not depend on the input resolution', () {
    final small = OpenCvEdgeDetector.detect(_desk(450, 600, _page));
    final large = OpenCvEdgeDetector.detect(_desk(1500, 2000, _page));
    expect(small, isNotNull);
    expect(large, isNotNull);
    expect(_iou(small!, _page), greaterThan(0.95));
    expect(_iou(large!, _page), greaterThan(0.95));
  }, skip: skip);

  test('a frame without a page returns null', () {
    final blank = img.Image(width: 400, height: 600, numChannels: 3);
    img.fill(blank, color: img.ColorRgb8(40, 40, 40));
    expect(OpenCvEdgeDetector.detect(blank), isNull);
  }, skip: skip);

  test('falls back to the Dart detector when OpenCV cannot load', () {
    var openCvCalls = 0;
    Quad? loadFailure() {
      openCvCalls++;
      throw ArgumentError('Couldn\'t resolve native function');
    }

    final first = EdgeDetection.run(
      openCv: loadFailure,
      dart: () => Quad.fullFrame,
    );
    expect(first, Quad.fullFrame);
    expect(EdgeDetection.lastBackend, EdgeDetectorBackend.dart);
    expect(EdgeDetection.openCvAvailable, isFalse);

    // Later calls on the same isolate skip OpenCV entirely.
    EdgeDetection.run(openCv: loadFailure, dart: () => null);
    expect(openCvCalls, 1);
  });

  test('an OpenCV error on one image only falls back for that image', () {
    final quad = EdgeDetection.run(
      openCv: () => throw cv.CvException(-1, msg: 'bad frame'),
      dart: () => Quad.standard,
    );
    expect(quad, Quad.standard);
    expect(EdgeDetection.openCvAvailable, isTrue);
  });

  test('forced Dart fallback still detects the synthetic page', () {
    EdgeDetection.forceDartFallback = true;
    final quad = tryDetectQuad(_desk(600, 800, _page));
    expect(EdgeDetection.lastBackend, EdgeDetectorBackend.dart);
    expect(quad, isNotNull);
    expect(_iou(quad!, _page), greaterThan(0.85));
  });

  group('live frames', () {
    test('YUV420 with padded rows and interleaved chroma keeps colors', () {
      final rgb = img.Image(width: 64, height: 48, numChannels: 3);
      img.fill(rgb, color: img.ColorRgb8(200, 40, 30));
      final frame = frameToRgb(yuvFrameFrom(rgb, sensorOrientation: 0))!;
      expect(frame.width, 64);
      expect(frame.height, 48);
      final i = (20 * 64 + 30) * 3;
      expect(frame.bytes[i], closeTo(200, 4));
      expect(frame.bytes[i + 1], closeTo(40, 4));
      expect(frame.bytes[i + 2], closeTo(30, 4));
    });

    test('landscape sensor frames are rotated upright', () {
      final rgb = img.Image(width: 64, height: 48, numChannels: 3);
      expect(frameToRgb(yuvFrameFrom(rgb, sensorOrientation: 90))!.rotation, 90);
      expect(frameToRgb(yuvFrameFrom(rgb, sensorOrientation: 270))!.rotation, 270);
      final portrait = img.Image(width: 48, height: 64, numChannels: 3);
      expect(frameToRgb(yuvFrameFrom(portrait, sensorOrientation: 90))!.rotation, 0);
    });

    test('detectFrameQuad returns portrait corners from a sensor frame', () {
      final upright = _desk(540, 720, _page);
      // A back camera with sensorOrientation 90 delivers the scene rotated
      // 90 degrees counter-clockwise.
      final sensor = img.copyRotate(upright, angle: 270);
      final quad = detectFrameQuad(yuvFrameFrom(sensor, sensorOrientation: 90));
      expect(EdgeDetection.lastBackend, EdgeDetectorBackend.openCv);
      expect(quad, isNotNull);
      expect(_iou(quad!, _page), greaterThan(0.93));
    }, skip: skip);
  });
}
