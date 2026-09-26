import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../geometry/quad.dart';
import 'edge_detection.dart';
import 'edge_detector.dart';
import 'opencv_edge_detector.dart';

/// A camera preview frame copied out of `CameraImage` so it can be sent to
/// a background isolate with `compute`.
class FrameData {
  FrameData({
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
    required this.formatGroup,
    this.sensorOrientation = 0,
  });

  /// Plane bytes: YUV420 (Y, U, V), NV21 (Y, VU) or BGRA8888 (one plane).
  final List<Uint8List> planes;
  final List<int> bytesPerRow;

  /// Distance between two samples of a plane (2 for interleaved chroma).
  final List<int?> bytesPerPixel;
  final int width;
  final int height;

  /// `ImageFormatGroup.name`: yuv420, nv21, bgra8888, ...
  final String formatGroup;

  /// Clockwise rotation that makes the sensor image upright in portrait.
  final int sensorOrientation;
}

/// Converts a preview frame to upright RGB and detects the page on it.
///
/// Runs on a background isolate. Corners are normalized to the upright
/// (portrait) frame, the same space as the captured photo after its EXIF
/// rotation, which is what the live overlay and auto-crop expect.
Quad? detectFrameQuad(FrameData data) {
  try {
    final frame = frameToRgb(data);
    if (frame == null) return null;
    return EdgeDetection.run(
      openCv: () => _openCvFrame(frame),
      dart: () => _dartFrame(frame),
    );
  } catch (_) {
    return null;
  }
}

/// Packed RGB frame, already rotated upright.
class RgbFrame {
  RgbFrame(this.bytes, this.width, this.height, this.rotation);

  final Uint8List bytes;
  final int width;
  final int height;

  /// Clockwise rotation still to apply (0, 90, 180 or 270).
  final int rotation;
}

/// Decodes [data] into packed RGB at up to ~1024 px on the long edge.
///
/// Rotation is only applied when the frame is landscape while the sensor
/// reports 90/270 (the usual phone case), so a platform that already
/// delivers upright frames is left alone.
RgbFrame? frameToRgb(FrameData data) {
  final w = data.width;
  final h = data.height;
  if (w <= 0 || h <= 0 || data.planes.isEmpty) return null;
  final step = math.max(1, math.max(w, h) ~/ 1024);
  final ow = w ~/ step;
  final oh = h ~/ step;
  final out = Uint8List(ow * oh * 3);
  final group = data.formatGroup;
  final p0 = data.planes[0];
  final rs0 = data.bytesPerRow.isNotEmpty && data.bytesPerRow[0] > 0
      ? data.bytesPerRow[0]
      : w;

  if (group == 'bgra8888') {
    var o = 0;
    for (var y = 0; y < oh; y++) {
      final row = y * step * rs0;
      for (var x = 0; x < ow; x++) {
        final i = row + x * step * 4;
        if (i + 2 < p0.length) {
          out[o] = p0[i + 2];
          out[o + 1] = p0[i + 1];
          out[o + 2] = p0[i];
        }
        o += 3;
      }
    }
  } else if (data.planes.length >= 2 && (group == 'yuv420' || group == 'nv21')) {
    final Uint8List uPlane;
    final Uint8List vPlane;
    final int uvRow;
    final int uStride;
    final int vStride;
    var uOff = 0;
    var vOff = 0;
    if (data.planes.length >= 3) {
      uPlane = data.planes[1];
      vPlane = data.planes[2];
      uvRow = data.bytesPerRow[1] > 0 ? data.bytesPerRow[1] : w ~/ 2;
      uStride = data.bytesPerPixel[1] ?? 1;
      vStride = data.bytesPerPixel[2] ?? 1;
    } else {
      // NV21: one interleaved V/U plane.
      uPlane = data.planes[1];
      vPlane = data.planes[1];
      uvRow = data.bytesPerRow[1] > 0 ? data.bytesPerRow[1] : w;
      uStride = 2;
      vStride = 2;
      uOff = 1;
    }
    var o = 0;
    for (var y = 0; y < oh; y++) {
      final sy = y * step;
      final yRow = sy * rs0;
      final cRow = (sy >> 1) * uvRow;
      for (var x = 0; x < ow; x++) {
        final sx = x * step;
        final yi = yRow + sx;
        final yv = yi < p0.length ? p0[yi] : 0;
        final cx = sx >> 1;
        final ui = cRow + cx * uStride + uOff;
        final vi = cRow + cx * vStride + vOff;
        final u = (ui < uPlane.length ? uPlane[ui] : 128) - 128;
        final v = (vi < vPlane.length ? vPlane[vi] : 128) - 128;
        out[o] = _u8(yv + 1.402 * v);
        out[o + 1] = _u8(yv - 0.344136 * u - 0.714136 * v);
        out[o + 2] = _u8(yv + 1.772 * u);
        o += 3;
      }
    }
  } else {
    // Unknown layout: treat the first plane as luminance.
    var o = 0;
    for (var y = 0; y < oh; y++) {
      final row = y * step * rs0;
      for (var x = 0; x < ow; x++) {
        final i = row + x * step;
        final g = i < p0.length ? p0[i] : 0;
        out[o] = g;
        out[o + 1] = g;
        out[o + 2] = g;
        o += 3;
      }
    }
  }

  final orientation = ((data.sensorOrientation % 360) + 360) % 360;
  final rotate = (orientation == 90 || orientation == 270) && ow > oh
      ? orientation
      : (orientation == 180 ? 180 : 0);
  return RgbFrame(out, ow, oh, rotate);
}

int _u8(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

Quad? _openCvFrame(RgbFrame frame) {
  final rgb = cv.Mat.zeros(frame.height, frame.width, cv.MatType.CV_8UC3);
  final mats = <cv.Mat>[rgb];
  try {
    rgb.data.setAll(0, frame.bytes);
    var bgr = cv.cvtColor(rgb, cv.COLOR_RGB2BGR);
    mats.add(bgr);
    final code = switch (frame.rotation) {
      90 => cv.ROTATE_90_CLOCKWISE,
      180 => cv.ROTATE_180,
      270 => cv.ROTATE_90_COUNTERCLOCKWISE,
      _ => null,
    };
    if (code != null) {
      bgr = cv.rotate(bgr, code);
      mats.add(bgr);
    }
    return OpenCvEdgeDetector.detectBgrMat(
      bgr,
      longEdge: OpenCvEdgeDetector.liveLongEdge,
    );
  } finally {
    for (final m in mats) {
      m.dispose();
    }
  }
}

Quad? _dartFrame(RgbFrame frame) {
  var image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.bytes.buffer,
    numChannels: 3,
  );
  if (frame.rotation != 0) {
    image = img.copyRotate(image, angle: frame.rotation);
  }
  return DocumentEdgeDetector.detect(image);
}
