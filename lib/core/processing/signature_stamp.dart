import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One placed signature. Safe to send into an isolate with the page JPEG.
class StampPayload {
  StampPayload({
    required this.png,
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final Uint8List png;
  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double rotation;
}

/// Height, as a fraction of the page, that keeps [signatureAspect]
/// (pixel width / pixel height) when [width] is a fraction of the page width.
double signatureHeightFraction({
  required double width,
  required double pageAspect,
  required double signatureAspect,
}) {
  if (pageAspect <= 0 || signatureAspect <= 0) return width;
  return width * pageAspect / signatureAspect;
}

/// Burns [marks] into [page]. [page] stays RGB; transparent ink is skipped.
///
/// The sprite is scaled uniformly to fit inside the requested box, so a
/// mismatched height cannot stretch the ink. The box center stays put.
img.Image stampImage(img.Image page, List<StampPayload> marks) {
  final base = page.convert(format: img.Format.uint8, numChannels: 3);
  for (final mark in marks) {
    final decoded = img.decodeImage(mark.png);
    if (decoded == null || decoded.width < 1 || decoded.height < 1) continue;
    final sprite = decoded.convert(format: img.Format.uint8, numChannels: 4);
    final boxW = (mark.width * base.width).round().clamp(1, base.width);
    final boxH = (mark.height * base.height).round().clamp(1, base.height);
    final scale = math.min(boxW / sprite.width, boxH / sprite.height);
    final outW = math.max(1, (sprite.width * scale).round());
    final outH = math.max(1, (sprite.height * scale).round());
    var resized = img.copyResize(
      sprite,
      width: outW,
      height: outH,
      interpolation: img.Interpolation.linear,
    );
    if (mark.rotation.abs() > 0.001) {
      resized = img.copyRotate(
        resized,
        angle: mark.rotation * 180 / math.pi,
        interpolation: img.Interpolation.linear,
      );
    }
    final dstX = (mark.centerX * base.width - resized.width / 2).round();
    final dstY = (mark.centerY * base.height - resized.height / 2).round();
    img.compositeImage(base, resized, dstX: dstX, dstY: dstY);
  }
  return base;
}
