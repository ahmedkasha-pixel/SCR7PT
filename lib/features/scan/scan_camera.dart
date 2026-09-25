import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

enum ScanCameraStatus { ready, denied, unavailable }

abstract class ScanCamera {
  Future<ScanCameraStatus> initialize();
  Widget buildPreview();
  Future<Uint8List> takePicture();
  Future<void> setFlash(bool enabled);
  Future<void> dispose();
}

class LiveScanCamera implements ScanCamera {
  CameraController? _controller;

  @override
  Future<ScanCameraStatus> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return ScanCameraStatus.unavailable;
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
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
    return CameraPreview(controller);
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
    } on CameraException {
      // Some devices have no torch. The shutter still works.
    }
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
