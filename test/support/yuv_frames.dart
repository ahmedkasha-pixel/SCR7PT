import 'dart:typed_data';

import 'package:docscan/core/processing/frame_quad.dart';
import 'package:image/image.dart' as img;

/// Builds an Android-style YUV_420_888 frame (interleaved chroma with a
/// pixel stride of 2 and padded rows) from an RGB image, the layout CameraX
/// delivers to `startImageStream`.
FrameData yuvFrameFrom(img.Image rgb, {int sensorOrientation = 90, int pad = 64}) {
  final w = rgb.width;
  final h = rgb.height;
  final rowY = w + pad;
  final cw = (w + 1) ~/ 2;
  final ch = (h + 1) ~/ 2;
  final rowUV = cw * 2 + pad;
  final yPlane = Uint8List(rowY * h);
  final uPlane = Uint8List(rowUV * ch);
  final vPlane = Uint8List(rowUV * ch);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = rgb.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      yPlane[y * rowY + x] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }
  for (var cy = 0; cy < ch; cy++) {
    for (var cx = 0; cx < cw; cx++) {
      var u = 0.0, v = 0.0, n = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final x = cx * 2 + dx, y = cy * 2 + dy;
          if (x >= w || y >= h) continue;
          final p = rgb.getPixel(x, y);
          final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
          u += -0.168736 * r - 0.331264 * g + 0.5 * b + 128;
          v += 0.5 * r - 0.418688 * g - 0.081312 * b + 128;
          n++;
        }
      }
      uPlane[cy * rowUV + cx * 2] = (u / n).round().clamp(0, 255);
      vPlane[cy * rowUV + cx * 2] = (v / n).round().clamp(0, 255);
    }
  }
  return FrameData(
    planes: [yPlane, uPlane, vPlane],
    bytesPerRow: [rowY, rowUV, rowUV],
    bytesPerPixel: [1, 2, 2],
    width: w,
    height: h,
    formatGroup: 'yuv420',
    sensorOrientation: sensorOrientation,
  );
}
