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
        ResolutionPreset.max,
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
