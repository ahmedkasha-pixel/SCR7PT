import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../l10n/app_localizations.dart';

class PlacementDraft {
  const PlacementDraft({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double rotation;
}

class SignaturePlaceScreen extends StatefulWidget {
  const SignaturePlaceScreen({
    super.key,
    required this.pageJpeg,
    required this.signaturePng,
  });

  final Uint8List pageJpeg;
  final Uint8List signaturePng;

  @override
  State<SignaturePlaceScreen> createState() => _SignaturePlaceScreenState();
}

class _SignaturePlaceScreenState extends State<SignaturePlaceScreen> {
  double _centerX = 0.5;
  double _centerY = 0.78;
  double _width = 0.42;
  double _rotation = 0;
  double _pageAspect = 0.7;
  double _sigAspect = 3;
  double _baseWidth = 0.42;
  double _baseRotation = 0;

  @override
  void initState() {
    super.initState();
    final page = img.findDecoderForData(widget.pageJpeg)?.startDecode(
      widget.pageJpeg,
    );
    final signature = img.findDecoderForData(widget.signaturePng)?.startDecode(
      widget.signaturePng,
    );
    if (page != null && page.height > 0) {
      _pageAspect = page.width / page.height;
    }
    if (signature != null && signature.height > 0) {
      _sigAspect = signature.width / signature.height;
    }
  }

  double get _height {
    if (_pageAspect <= 0 || _sigAspect <= 0) return 0.12;
    return (_width / _sigAspect / _pageAspect).clamp(0.04, 0.8);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.placeSignature)),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final box = _contain(
                    constraints.biggest,
                    Size(_pageAspect, 1),
                  );
                  final mark = Rect.fromCenter(
                    center: Offset(
                      box.left + _centerX * box.width,
                      box.top + _centerY * box.height,
                    ),
                    width: _width * box.width,
                    height: _height * box.height,
                  );
                  return Stack(
                    children: [
                      Positioned.fromRect(
                        rect: box,
                        child: ColoredBox(
                          color: const Color(0xFFF4F2EE),
                          child: Image.memory(
                            widget.pageJpeg,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: mark,
                        child: GestureDetector(
                          onScaleStart: (_) {
                            _baseWidth = _width;
                            _baseRotation = _rotation;
                          },
                          onScaleUpdate: (details) {
                            setState(() {
                              _width = (_baseWidth * details.scale).clamp(
                                0.16,
                                0.9,
                              );
                              _rotation = _baseRotation + details.rotation;
                              _centerX = (_centerX +
                                      details.focalPointDelta.dx / box.width)
                                  .clamp(0.08, 0.92);
                              _centerY = (_centerY +
                                      details.focalPointDelta.dy / box.height)
                                  .clamp(0.08, 0.92);
                            });
                          },
                          child: Transform.rotate(
                            angle: _rotation,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFF2563EB),
                                  width: 2,
                                ),
                              ),
                              child: Image.memory(
                                widget.signaturePng,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final handle in const [
                        Alignment.topLeft,
                        Alignment.topRight,
                        Alignment.bottomLeft,
                        Alignment.bottomRight,
                      ])
                        _resizeHandle(box, mark, handle),
                    ],
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton(
                key: const Key('confirm-placement'),
                onPressed: () {
                  Navigator.pop(
                    context,
                    PlacementDraft(
                      centerX: _centerX,
                      centerY: _centerY,
                      width: _width,
                      height: _height,
                      rotation: _rotation,
                    ),
                  );
                },
                child: Text(l10n.confirmPlace),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resizeHandle(Rect pageBox, Rect mark, Alignment alignment) {
    final point = alignment.withinRect(mark);
    const size = 18.0;
    return Positioned(
      left: point.dx - size / 2,
      top: point.dy - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        onPanUpdate: (details) => _dragHandle(details.delta, pageBox, alignment),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  void _dragHandle(Offset delta, Rect pageBox, Alignment alignment) {
    if (pageBox.width <= 0 || pageBox.height <= 0) return;
    final dx = delta.dx / pageBox.width;
    final grow = alignment.x * dx;
    setState(() {
      final next = (_width + grow).clamp(0.16, 0.92);
      final applied = next - _width;
      _width = next;
      _centerX = (_centerX + alignment.x * applied / 2).clamp(0.08, 0.92);
      final heightDelta = alignment.y * delta.dy / pageBox.height;
      final widthFromHeight = heightDelta * _sigAspect * _pageAspect;
      final nextH = (_width + widthFromHeight).clamp(0.16, 0.92);
      final appliedH = nextH - _width;
      _width = nextH;
      _centerY = (_centerY +
              alignment.y * (appliedH / _sigAspect / _pageAspect) / 2)
          .clamp(0.08, 0.92);
    });
  }

  Rect _contain(Size outer, Size inner) {
    final scale = math.min(outer.width / inner.width, outer.height / inner.height);
    final width = inner.width * scale;
    final height = inner.height * scale;
    return Rect.fromLTWH(
      (outer.width - width) / 2,
      (outer.height - height) / 2,
      width,
      height,
    );
  }
}
