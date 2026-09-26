import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../geometry/quad.dart';
import 'edge_detector.dart';
import 'opencv_edge_detector.dart';

/// Which detector produced the last result on this isolate.
enum EdgeDetectorBackend { openCv, dart }

/// Entry point for page-edge detection.
///
/// Uses [OpenCvEdgeDetector] (the port of the Python prototype). If the
/// native OpenCV library cannot be loaded on this isolate, it switches to the
/// pure-Dart [DocumentEdgeDetector] for the rest of the isolate's life. An
/// OpenCV error on a single image falls back for that image only.
class EdgeDetection {
  const EdgeDetection._();

  static bool _openCvUnavailable = false;

  /// Test hook: force the pure-Dart detector.
  static bool forceDartFallback = false;

  /// Backend used by the most recent call on this isolate.
  static EdgeDetectorBackend lastBackend = EdgeDetectorBackend.openCv;

  /// Clears the "OpenCV unavailable" flag and the test override.
  @visibleForTesting
  static void resetForTest() {
    _openCvUnavailable = false;
    forceDartFallback = false;
    lastBackend = EdgeDetectorBackend.openCv;
  }

  /// Whether OpenCV is still considered usable on this isolate.
  static bool get openCvAvailable => !_openCvUnavailable && !forceDartFallback;

  /// Normalized document corners, or null when no page is found.
  static Quad? detect(img.Image source) {
    return run(
      openCv: () => OpenCvEdgeDetector.detect(source),
      dart: () => DocumentEdgeDetector.detect(source),
    );
  }

  /// Runs [openCv] and falls back to [dart] when OpenCV is missing or fails.
  static Quad? run({
    required Quad? Function() openCv,
    required Quad? Function() dart,
  }) {
    if (openCvAvailable) {
      try {
        final quad = openCv();
        lastBackend = EdgeDetectorBackend.openCv;
        return quad;
      } on cv.CvException {
        // OpenCV is loaded but rejected this frame: fall back once.
      } catch (_) {
        // Native library missing or failed to load (ArgumentError from the
        // FFI lookup, UnsupportedError, ...): stop trying on this isolate.
        _openCvUnavailable = true;
      }
    }
    lastBackend = EdgeDetectorBackend.dart;
    return dart();
  }
}
