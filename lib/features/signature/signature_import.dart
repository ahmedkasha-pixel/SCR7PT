import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../../app/app_scope.dart';
import '../../core/processing/signature_extract.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import '../scan/scan_camera.dart';

File signatureFile(String path) => File(path);

class Checkerboard extends StatelessWidget {
  const Checkerboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _CheckerPainter(),
      child: child,
    );
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()..color = const Color(0xFFE8E9EA);
    final dark = Paint()..color = const Color(0xFFB7BCC4);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final alt = ((x / cell).floor() + (y / cell).floor()).isOdd;
        if (alt) canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CropRequest {
  CropRequest(this.bytes, this.left, this.top, this.right, this.bottom);

  final Uint8List bytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

Uint8List cropNormalized(CropRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('unsupported-image');
  }
  final left = (request.left * decoded.width).round().clamp(0, decoded.width - 1);
  final top = (request.top * decoded.height).round().clamp(0, decoded.height - 1);
  final right = (request.right * decoded.width).round().clamp(left + 1, decoded.width);
  final bottom = (request.bottom * decoded.height).round().clamp(
    top + 1,
    decoded.height,
  );
  final cropped = img.copyCrop(
    decoded,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

class SignatureCameraScreen extends StatefulWidget {
  const SignatureCameraScreen({super.key});

  @override
  State<SignatureCameraScreen> createState() => _SignatureCameraScreenState();
}

class _SignatureCameraScreenState extends State<SignatureCameraScreen> {
  ScanCamera? _camera;
  ScanCameraStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final camera = AppScope.of(context).createCamera();
    final status = await camera.initialize();
    if (!mounted) {
      await camera.dispose();
      return;
    }
    setState(() {
      _camera = camera;
      _status = status;
    });
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ready = _status == ScanCameraStatus.ready && _camera != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fromCamera)),
      body: Column(
        children: [
          Expanded(
            child: ready
                ? _camera!.buildPreview()
                : const Center(child: CircularProgressIndicator()),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const Key('signature-shutter'),
                onPressed: ready ? _capture : null,
                icon: const Icon(Icons.photo_camera),
                label: Text(l10n.fromCamera),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _capture() async {
    final bytes = await _camera!.takePicture();
    if (!mounted) return;
    Navigator.pop(context, bytes);
  }
}

class SignatureDrawScreen extends StatefulWidget {
  const SignatureDrawScreen({super.key});

  @override
  State<SignatureDrawScreen> createState() => _SignatureDrawScreenState();
}

class _SignatureDrawScreenState extends State<SignatureDrawScreen> {
  final _strokes = <List<Offset>>[];
  final _boundary = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawSignature)),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: RepaintBoundary(
                    key: _boundary,
                    child: GestureDetector(
                      onPanStart: (details) {
                        setState(() => _strokes.add([details.localPosition]));
                      },
                      onPanUpdate: (details) {
                        setState(() => _strokes.last.add(details.localPosition));
                      },
                      child: CustomPaint(
                        painter: _InkPainter(_strokes),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _strokes.isEmpty
                        ? null
                        : () => setState(_strokes.clear),
                    child: Text(l10n.resetCorners),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _strokes.isEmpty ? null : _save,
                      child: Text(l10n.cropDone),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null || !mounted) return;
    Navigator.pop(context, data.buffer.asUint8List());
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x00FFFFFF));
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.isNotEmpty) {
          canvas.drawCircle(stroke.first, 2, paint..style = PaintingStyle.fill);
          paint.style = PaintingStyle.stroke;
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}

class SignatureImportScreen extends StatefulWidget {
  const SignatureImportScreen({
    super.key,
    required this.bytes,
    this.startAtCleanup = false,
    this.initialPreview,
  });

  final Uint8List bytes;
  final bool startAtCleanup;

  /// Optional PNG so a screenshot can show the checkerboard immediately.
  final Uint8List? initialPreview;

  @override
  State<SignatureImportScreen> createState() => _SignatureImportScreenState();
}

class _SignatureImportScreenState extends State<SignatureImportScreen> {
  late bool _cleanup = widget.startAtCleanup;
  Uint8List? _cropped;
  Uint8List? _preview;
  double _left = 0.12;
  double _top = 0.28;
  double _right = 0.88;
  double _bottom = 0.72;
  double _cleanliness = 0.55;
  SignatureInk _ink = SignatureInk.original;
  bool _busy = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
    if (_cleanup) {
      _cropped = widget.bytes;
      if (_preview == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _extract());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_cleanup ? l10n.removeBackground : l10n.editPage),
      ),
      body: _cleanup ? _cleanupBody(l10n) : _cropBody(l10n),
    );
  }

  Widget _cropBody(AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanUpdate: (details) => _moveCrop(
                    details.delta,
                    constraints.biggest,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(widget.bytes, fit: BoxFit.contain),
                      CustomPaint(
                        painter: _CropPainter(
                          left: _left,
                          top: _top,
                          right: _right,
                          bottom: _bottom,
                        ),
                      ),
                    ],
                  ),
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
              key: const Key('signature-crop-done'),
              onPressed: _busy ? null : _applyCrop,
              child: Text(l10n.cropDone),
            ),
          ),
        ),
      ],
    );
  }

  void _moveCrop(Offset delta, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    setState(() {
      var left = (_left + dx).clamp(0.0, 0.9);
      var top = (_top + dy).clamp(0.0, 0.9);
      var right = (_right + dx).clamp(0.1, 1.0);
      var bottom = (_bottom + dy).clamp(0.1, 1.0);
      if (right - left < 0.12) {
        left = _left;
        right = _right;
      }
      if (bottom - top < 0.08) {
        top = _top;
        bottom = _bottom;
      }
      _left = left.toDouble();
      _top = top.toDouble();
      _right = right.toDouble();
      _bottom = bottom.toDouble();
    });
  }

  Future<void> _applyCrop() async {
    setState(() => _busy = true);
    try {
      final cropped = await compute(
        cropNormalized,
        CropRequest(widget.bytes, _left, _top, _right, _bottom),
      );
      if (!mounted) return;
      setState(() {
        _cropped = cropped;
        _cleanup = true;
        _busy = false;
      });
      await _extract();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _cleanupBody(AppLocalizations l10n) {
    final preview = _preview;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Checkerboard(
              child: SizedBox.expand(
                child: preview == null
                    ? const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Image.memory(
                        preview,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.cleanliness, style: Theme.of(context).textTheme.titleSmall),
              Slider(
                key: const Key('signature-cleanliness'),
                value: _cleanliness,
                onChanged: (value) {
                  setState(() => _cleanliness = value);
                  _extract();
                },
              ),
              Text(l10n.inkColor, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final ink in SignatureInk.values)
                    ChoiceChip(
                      key: Key('ink-${ink.name}'),
                      label: Text(_inkLabel(l10n, ink)),
                      selected: _ink == ink,
                      onSelected: (_) {
                        setState(() => _ink = ink);
                        _extract();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('signature-save'),
              onPressed: preview == null ? null : _save,
              child: Text(l10n.save),
            ),
          ),
        ),
      ],
    );
  }

  String _inkLabel(AppLocalizations l10n, SignatureInk ink) {
    switch (ink) {
      case SignatureInk.original:
        return l10n.inkOriginal;
      case SignatureInk.black:
        return l10n.inkBlack;
      case SignatureInk.blue:
        return l10n.inkBlue;
    }
  }

  Future<void> _extract() async {
    final source = _cropped;
    if (source == null) return;
    final token = ++_token;
    final png = await compute(
      extractSignaturePng,
      ExtractRequest(
        bytes: source,
        cleanliness: _cleanliness,
        inkName: _ink.name,
      ),
    );
    if (!mounted || token != _token) return;
    setState(() => _preview = png);
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null) return;
    final l10n = AppLocalizations.of(context);
    final name = await promptForName(
      context,
      title: l10n.addSignature,
      label: l10n.signatureName,
      initial: l10n.signatureTitle,
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).signatures.create(name: name, png: preview);
    if (!mounted) return;
    Navigator.pop(context, true);
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      left * size.width,
      top * size.height,
      right * size.width,
      bottom * size.height,
    );
    final shade = Paint()..color = const Color(0x990F172A);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(rect),
      ),
      shade,
    );
    final border = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.left != left ||
      oldDelegate.top != top ||
      oldDelegate.right != right ||
      oldDelegate.bottom != bottom;
}
