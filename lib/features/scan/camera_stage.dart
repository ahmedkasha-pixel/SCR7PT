import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/geometry/quad.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wordmark.dart';
import 'scan_camera.dart';

class CameraStage extends StatelessWidget {
  const CameraStage({
    super.key,
    required this.camera,
    required this.status,
    required this.flashOn,
    required this.hasTorch,
    required this.manual,
    required this.pageCount,
    required this.onCapture,
    required this.onGallery,
    required this.onFlash,
    required this.onRetry,
    required this.onClose,
    required this.onManualChanged,
    this.detectedQuad,
  });

  final ScanCamera? camera;
  final ScanCameraStatus? status;
  final bool flashOn;
  final bool hasTorch;
  final bool manual;
  final int pageCount;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onFlash;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final ValueChanged<bool> onManualChanged;
  final Quad? detectedQuad;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ready = status == ScanCameraStatus.ready && camera != null;
    final liveQuad = !manual ? detectedQuad : null;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            camera!.buildPreview()
          else
            _Message(status: status, onGallery: onGallery, onRetry: onRetry),
          if (ready && liveQuad != null)
            IgnorePointer(
              child: AnimatedLiveQuadOverlay(quad: liveQuad),
            )
          else
            const IgnorePointer(child: _CropFrame()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton(
                        key: const Key('camera-close'),
                        onPressed: onClose,
                        child: Text(
                          l10n.cancel,
                          style: AppTheme.text(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Wordmark(size: 18, color: Colors.white),
                      const Spacer(),
                      _CountPill(count: pageCount),
                    ],
                  ),
                  const Spacer(),
                  _ModeSwitch(manual: manual, onChanged: onManualChanged),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundAction(
                        key: const Key('gallery-button'),
                        icon: Icons.photo_library_outlined,
                        label: l10n.gallery,
                        onPressed: onGallery,
                      ),
                      _Shutter(
                        key: const Key('shutter-button'),
                        onPressed: ready ? onCapture : null,
                      ),
                      if (hasTorch)
                        _RoundAction(
                          key: const Key('flash-toggle-button'),
                          icon: flashOn ? Icons.flashlight_on : Icons.flashlight_off,
                          label: l10n.flash,
                          onPressed: ready ? onFlash : null,
                        )
                      else
                        const SizedBox(width: 56, height: 56),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedLiveQuadOverlay extends StatelessWidget {
  const AnimatedLiveQuadOverlay({super.key, required this.quad});

  final Quad quad;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Quad>(
      tween: _QuadTween(end: quad),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      builder: (context, animatedQuad, _) {
        return CustomPaint(
          painter: _LiveQuadPainter(quad: animatedQuad),
        );
      },
    );
  }
}

class _QuadTween extends Tween<Quad> {
  _QuadTween({required Quad end}) : super(end: end);

  @override
  Quad lerp(double t) {
    if (begin == null) return end!;
    return begin!.lerp(end!, t);
  }
}

class _LiveQuadPainter extends CustomPainter {
  const _LiveQuadPainter({required this.quad});

  final Quad quad;

  @override
  void paint(Canvas canvas, Size size) {
    Offset toScreen(NormPoint p) => Offset(p.x * size.width, p.y * size.height);

    final tl = toScreen(quad.topLeft);
    final tr = toScreen(quad.topRight);
    final br = toScreen(quad.bottomRight);
    final bl = toScreen(quad.bottomLeft);

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    // Semi-transparent brand blue fill: #2563EB with 0.22 opacity
    final fillPaint = Paint()
      ..color = const Color(0x382563EB)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Glowing border: brand blue #2563EB strokeWidth 3
    final strokePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // Accent corner markers
    final cornerDotPaint = Paint()
      ..color = const Color(0xFF06B6D4) // Accent cyan
      ..style = PaintingStyle.fill;
    const dotR = 6.0;
    canvas.drawCircle(tl, dotR, cornerDotPaint);
    canvas.drawCircle(tr, dotR, cornerDotPaint);
    canvas.drawCircle(br, dotR, cornerDotPaint);
    canvas.drawCircle(bl, dotR, cornerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _LiveQuadPainter oldDelegate) =>
      oldDelegate.quad != quad;
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('page-counter'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0F172A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        l10n.pagesCount(count),
        style: AppTheme.text(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.manual, required this.onChanged});

  final bool manual;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0F172A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            key: const Key('mode-auto'),
            label: l10n.autoMode,
            selected: !manual,
            onTap: () => onChanged(false),
          ),
          _ModeChip(
            key: const Key('mode-manual'),
            label: l10n.manualMode,
            selected: manual,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTheme.text(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropFrame extends StatelessWidget {
  const _CropFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.78,
        heightFactor: 0.62,
        child: CustomPaint(painter: _BracketPainter()),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const arm = 28.0;
    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final signs = <Offset>[
      const Offset(1, 1),
      const Offset(-1, 1),
      const Offset(-1, -1),
      const Offset(1, -1),
    ];
    for (var i = 0; i < 4; i++) {
      final origin = corners[i];
      final sign = signs[i];
      canvas.drawLine(origin, origin + Offset(arm * sign.dx, 0), paint);
      canvas.drawLine(origin, origin + Offset(0, arm * sign.dy), paint);
      canvas.drawCircle(origin, 6, Paint()..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Message extends StatelessWidget {
  const _Message({
    required this.status,
    required this.onGallery,
    required this.onRetry,
  });

  final ScanCameraStatus? status;
  final VoidCallback onGallery;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final denied = status == ScanCameraStatus.denied;
    final waiting = status == null;
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (waiting)
                const CircularProgressIndicator(color: AppColors.primary),
              if (!waiting)
                Icon(
                  denied
                      ? Icons.no_photography_outlined
                      : Icons.camera_alt_outlined,
                  color: Colors.white,
                  size: 48,
                ),
              const SizedBox(height: 16),
              Text(
                waiting
                    ? l10n.startingCamera
                    : denied
                    ? l10n.cameraPermissionBody
                    : l10n.cameraUnavailableTitle,
                textAlign: TextAlign.center,
                style: AppTheme.text(color: Colors.white),
              ),
              if (denied) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: openAppSettings,
                  child: Text(l10n.openSettings),
                ),
              ],
              if (!waiting && !denied) ...[
                const SizedBox(height: 16),
                TextButton(onPressed: onRetry, child: Text(l10n.retry)),
              ],
              const SizedBox(height: 8),
              TextButton(onPressed: onGallery, child: Text(l10n.gallery)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xCC0F172A),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTheme.text(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
