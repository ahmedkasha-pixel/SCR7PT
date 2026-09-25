import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/geometry/quad.dart';
import '../core/theme/app_theme.dart';

class CropOverlay extends StatelessWidget {
  const CropOverlay({
    super.key,
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.quad,
    required this.onChanged,
  });

  final Uint8List bytes;
  final int imageWidth;
  final int imageHeight;
  final Quad quad;
  final void Function(CropCorner corner, NormPoint point) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(imageWidth.toDouble(), imageHeight.toDouble()),
          box,
        );
        final rect = Alignment.center.inscribe(
          fitted.destination,
          Offset.zero & box,
        );

        Offset toScreen(NormPoint point) => Offset(
          rect.left + point.x * rect.width,
          rect.top + point.y * rect.height,
        );

        NormPoint toNorm(Offset offset) => NormPoint(
          ((offset.dx - rect.left) / rect.width).clamp(0.0, 1.0).toDouble(),
          ((offset.dy - rect.top) / rect.height).clamp(0.0, 1.0).toDouble(),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.memory(
                bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _QuadPainter(rect: rect, quad: quad),
                ),
              ),
            ),
            for (final corner in CropCorner.values)
              Positioned(
                left: toScreen(quad.point(corner)).dx - 22,
                top: toScreen(quad.point(corner)).dy - 22,
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final render = context.findRenderObject() as RenderBox;
                    final local = render.globalToLocal(details.globalPosition);
                    onChanged(corner, toNorm(local));
                  },
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const SizedBox(width: 22, height: 22),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.rect, required this.quad});

  final Rect rect;
  final Quad quad;

  Offset _point(NormPoint point) => Offset(
    rect.left + point.x * rect.width,
    rect.top + point.y * rect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(_point(quad.topLeft).dx, _point(quad.topLeft).dy)
      ..lineTo(_point(quad.topRight).dx, _point(quad.topRight).dy)
      ..lineTo(_point(quad.bottomRight).dx, _point(quad.bottomRight).dy)
      ..lineTo(_point(quad.bottomLeft).dx, _point(quad.bottomLeft).dy)
      ..close();
    final shade = Path()
      ..addRect(rect)
      ..addPath(path, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) => true;
}
