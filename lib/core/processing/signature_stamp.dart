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

/// Burns [marks] into [page]. [page] stays RGB; transparent ink is skipped.
img.Image stampImage(img.Image page, List<StampPayload> marks) {
  final base = page.convert(format: img.Format.uint8, numChannels: 3);
  for (final mark in marks) {
    final decoded = img.decodeImage(mark.png);
    if (decoded == null) continue;
    final sprite = decoded.convert(format: img.Format.uint8, numChannels: 4);
    final pxW = (mark.width * base.width).round().clamp(1, base.width);
    final pxH = (mark.height * base.height).round().clamp(1, base.height);
    var resized = img.copyResize(
      sprite,
      width: pxW,
      height: pxH,
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
