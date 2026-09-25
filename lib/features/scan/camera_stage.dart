import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import 'scan_camera.dart';

class CameraStage extends StatelessWidget {
  const CameraStage({
    super.key,
    required this.camera,
    required this.status,
    required this.flashOn,
    required this.onCapture,
    required this.onGallery,
    required this.onFlash,
    required this.onRetry,
  });

  final ScanCamera? camera;
  final ScanCameraStatus? status;
  final bool flashOn;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onFlash;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ready = status == ScanCameraStatus.ready && camera != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.cameraTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  camera!.buildPreview()
                else
                  _Message(
                    status: status,
                    onGallery: onGallery,
                    onRetry: onRetry,
                  ),
                if (ready)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white70, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  Text(
                    l10n.scanHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
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
                      _RoundAction(
                        icon: flashOn ? Icons.flash_on : Icons.flash_off,
                        label: l10n.flash,
                        onPressed: ready ? onFlash : null,
                      ),
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
      color: const Color(0xFF111111),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (waiting) const CircularProgressIndicator(color: Colors.white),
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
                style: const TextStyle(color: Colors.white),
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
    return IconButton.filled(
      onPressed: onPressed,
      iconSize: 36,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size(76, 76),
      ),
      icon: const Icon(Icons.camera),
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
        IconButton(onPressed: onPressed, color: Colors.white, icon: Icon(icon)),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
