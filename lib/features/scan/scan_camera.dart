import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

enum ScanCameraStatus { ready, denied, unavailable }

abstract class ScanCamera {
  Future<ScanCameraStatus> initialize();
  Widget buildPreview();
  Future<Uint8List> takePicture();
  Future<void> setFlash(bool enabled);
  bool get hasTorch;
  bool get isTorchOn;
  double? get sensorAspectRatio;

  /// Clockwise rotation (0, 90, 180, 270) that makes preview frames upright.
  int get sensorOrientation;
  void startImageStream(void Function(CameraImage image) onAvailable);
  Future<void> stopImageStream();
  Future<void> dispose();
}

class LiveScanCamera implements ScanCamera {
  CameraController? _controller;
  bool _hasTorch = false;
  bool _isTorchOn = false;

  @override
  bool get hasTorch => _hasTorch;

  @override
  bool get isTorchOn => _isTorchOn;

  @override
  double? get sensorAspectRatio {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    final aspect = controller.value.aspectRatio;
    if (aspect <= 0) return null;
    // CameraController.value.aspectRatio is width/height of the raw sensor buffer
    // (landscape orientation, e.g. 4/3 ~ 1.333). In portrait display, we invert:
    // portrait aspect = height/width = 1 / aspect (e.g. 3/4 = 0.75).
    return aspect > 1.0 ? 1.0 / aspect : aspect;
  }

  @override
  int get sensorOrientation =>
      _controller?.description.sensorOrientation ?? 90;

  @override
  Future<ScanCameraStatus> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return ScanCameraStatus.unavailable;
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // Use ResolutionPreset.high (1280x720 or 1080p, consistently 4:3 or 16:9 matching sensor)
      // to guarantee preview and still-capture share identical framing aspect ratio (4:3)
      // without sensor cropping divergence seen in ResolutionPreset.max.
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
      // Probe torch capability
      try {
        await controller.setFlashMode(FlashMode.off);
        _hasTorch = true;
      } catch (_) {
        _hasTorch = false;
      }
      return ScanCameraStatus.ready;
    } on CameraException catch (error) {
      if (_denied(error.code)) return ScanCameraStatus.denied;
      return ScanCameraStatus.unavailable;
    } catch (_) {
      return ScanCameraStatus.unavailable;
    }
  }

  bool _denied(String code) {
    return code == 'CameraAccessDenied' ||
        code == 'CameraAccessDeniedWithoutPrompt' ||
        code == 'CameraAccessRestricted';
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    // Calculate true portrait aspect ratio:
    // controller.value.aspectRatio in landscape is width/height (e.g. 4/3 = 1.333).
    // In portrait, the preview aspect ratio is 1 / aspectRatio (e.g. 3/4 = 0.75).
    final rawAspect = controller.value.aspectRatio;
    final portraitAspect = rawAspect > 1.0 ? 1.0 / rawAspect : rawAspect;

    return ClipRect(
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxWidth / portraitAspect,
                  child: CameraPreview(controller),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Future<Uint8List> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera is not ready.');
    }
    final file = await controller.takePicture();
    return file.readAsBytes();
  }

  @override
  Future<void> setFlash(bool enabled) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      _isTorchOn = enabled;
      _hasTorch = true;
    } on CameraException {
      _hasTorch = false;
      _isTorchOn = false;
      // Some devices have no torch. The shutter still works.
    }
  }

  @override
  void startImageStream(void Function(CameraImage image) onAvailable) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (!controller.value.isStreamingImages) {
        controller.startImageStream(onAvailable);
      }
    } catch (_) {}
  }

  @override
  Future<void> stopImageStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_isTorchOn) {
      try {
        await _controller?.setFlashMode(FlashMode.off);
      } catch (_) {}
      _isTorchOn = false;
    }
    await _controller?.dispose();
    _controller = null;
  }
}
