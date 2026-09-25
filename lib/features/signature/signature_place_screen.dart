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
                  return Stack(
                    children: [
                      Positioned.fromRect(
                        rect: box,
                        child: Image.memory(
                          widget.pageJpeg,
                          fit: BoxFit.fill,
                        ),
                      ),
                      Positioned(
                        left: box.left + (_centerX - _width / 2) * box.width,
                        top: box.top + (_centerY - _height / 2) * box.height,
                        width: _width * box.width,
                        height: _height * box.height,
                        child: GestureDetector(
                          onScaleStart: (_) {
                            _baseWidth = _width;
                            _baseRotation = _rotation;
                          },
                          onScaleUpdate: (details) {
                            setState(() {
                              _width = (_baseWidth * details.scale).clamp(
                                0.12,
                                0.9,
                              );
                              _rotation = _baseRotation + details.rotation;
                              _centerX = (_centerX +
                                      details.focalPointDelta.dx / box.width)
                                  .clamp(0.05, 0.95);
                              _centerY = (_centerY +
                                      details.focalPointDelta.dy / box.height)
                                  .clamp(0.05, 0.95);
                            });
                          },
                          child: Transform.rotate(
                            angle: _rotation,
                            child: Image.memory(
                              widget.signaturePng,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                      ),
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
