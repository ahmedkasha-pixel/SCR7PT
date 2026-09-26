import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../app/app_scope.dart';
import '../../core/geometry/quad.dart';
import '../../core/naming/document_name.dart';
import '../../core/processing/frame_quad.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import 'camera_stage.dart';
import 'page_editor.dart';
import 'scan_camera.dart';
import 'scan_session.dart';

/// A saved document that a scan session appends new pages to.
class ScanAppendTarget {
  const ScanAppendTarget({required this.document, required this.existingPages});

  final DocumentRecord document;

  /// How many pages the document already has (counts toward the limit).
  final int existingPages;
}

/// Camera → crop/edit → save. With [appendTo] set, the finished pages are
/// added to that saved document and the route pops with the number added.
class ScanFlow extends StatefulWidget {
  const ScanFlow({super.key, this.folderId, this.appendTo});

  final String? folderId;
  final ScanAppendTarget? appendTo;

  @override
  State<ScanFlow> createState() => _ScanFlowState();
}

class _ScanFlowState extends State<ScanFlow> with WidgetsBindingObserver {
  late final ScanSession _session = ScanSession(
    folderId: widget.folderId,
    existingPages: widget.appendTo?.existingPages ?? 0,
  );
  ScanCamera? _camera;
  ScanCameraStatus? _status;
  bool _editing = false;
  bool _flash = false;
  bool _manual = false;
  bool _forcePop = false;
  bool _isCapturing = false;

  // Real-time edge detection state
  Quad? _liveQuad;
  bool _isProcessingFrame = false;
  int _lastFrameTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session.pageSizeMode =
        AppScope.of(context).settings.settings.pageSizeMode;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_camera == null || _status != ScanCameraStatus.ready) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Turn off torch when app goes to background
      if (_flash) {
        _camera?.setFlash(false);
      }
      _camera?.stopImageStream();
    } else if (state == AppLifecycleState.resumed && !_editing) {
      // Restore torch per setting on resume
      final autoTorch = AppScope.of(context).settings.settings.autoTorch;
      if (autoTorch && _camera?.hasTorch == true) {
        _camera?.setFlash(true);
        if (mounted) setState(() => _flash = true);
      }
      _startLiveStreamIfReady();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    _camera?.setFlash(false);
    _camera?.dispose();
    _session.dispose();
    super.dispose();
  }

  void _onSession() {
    if (_editing && _session.pages.isEmpty && mounted) {
      setState(() => _editing = false);
      _openCamera();
    }
  }

  Future<void> _openCamera() async {
    final createCamera = AppScope.of(context).createCamera;
    await _camera?.dispose();
    if (!mounted) return;
    final camera = createCamera();
    final status = await camera.initialize();
    if (!mounted || _editing) {
      await camera.dispose();
      return;
    }

    final autoTorch = AppScope.of(context).settings.settings.autoTorch;
    var initialFlash = false;
    if (autoTorch && camera.hasTorch) {
      await camera.setFlash(true);
      initialFlash = true;
    } else {
      await camera.setFlash(false);
    }

    setState(() {
      _camera = camera;
      _status = status;
      _flash = initialFlash;
      _liveQuad = null;
    });

    if (status == ScanCameraStatus.ready) {
      _startLiveStreamIfReady();
    }
  }

  void _startLiveStreamIfReady() {
    final camera = _camera;
    if (camera == null) return;
    camera.startImageStream(_onCameraFrame);
  }

  int _consecutiveDetections = 0;
  Quad? _candidateQuad;

  void _onCameraFrame(CameraImage frame) {
    if (_isProcessingFrame || _manual || _editing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle to ~8 fps (125ms gap)
    if (now - _lastFrameTime < 125) return;
    _lastFrameTime = now;
    _isProcessingFrame = true;

    _processFrameIsolate(frame).then((detected) {
      if (!mounted || _manual || _editing) return;
      if (detected != null && detected.isUsable) {
        if (_candidateQuad != null && _candidateQuad!.isNear(detected, threshold: 0.06)) {
          _consecutiveDetections++;
        } else {
          _consecutiveDetections = 1;
          _candidateQuad = detected;
        }

        // Require at least 2 consecutive consistent frames before showing/updating overlay
        if (_consecutiveDetections >= 2) {
          final smoothed = _liveQuad != null
              ? _liveQuad!.lerp(detected, 0.35)
              : detected;
          setState(() => _liveQuad = smoothed);
        }
      } else {
        _consecutiveDetections = 0;
        _candidateQuad = null;
        setState(() => _liveQuad = null);
      }
    }).catchError((_) {
      // Ignore background detection errors
    }).whenComplete(() {
      _isProcessingFrame = false;
    });
  }

  Future<Quad?> _processFrameIsolate(CameraImage frame) async {
    return compute(
      detectFrameQuad,
      FrameData(
        planes: [for (final p in frame.planes) p.bytes],
        bytesPerRow: [for (final p in frame.planes) p.bytesPerRow],
        bytesPerPixel: [for (final p in frame.planes) p.bytesPerPixel],
        width: frame.width,
        height: frame.height,
        formatGroup: frame.format.group.name,
        sensorOrientation: _camera?.sensorOrientation ?? 0,
      ),
    );
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _isCapturing) return;
    setState(() => _isCapturing = true);

    // Immediate tactile feedback
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    final swTotal = Stopwatch()..start();
    try {
      // 1. Immediately stop the stream so CPU is 100% free for shutter
      await camera.stopImageStream();
      final capturedQuad = _liveQuad;

      // 2. Take picture at native sensor speed
      final swTake = Stopwatch()..start();
      final bytes = await camera.takePicture();
      swTake.stop();

      // 3. Instant session enqueue - lands in crop view without blocking on heavy warp
      final swAdd = Stopwatch()..start();
      await _session.addBytes(bytes, manual: _manual, detectedQuad: capturedQuad);
      swAdd.stop();

      swTotal.stop();
      debugPrint(
        '[TIMING] capture total: ${swTotal.elapsedMilliseconds}ms '
        '(takePicture: ${swTake.elapsedMilliseconds}ms, addBytes: ${swAdd.elapsedMilliseconds}ms)',
      );

      if (!mounted) return;
      await _camera?.dispose();
      setState(() {
        _camera = null;
        _editing = true;
        _isCapturing = false;
        _liveQuad = null;
      });
    } on StateError {
      setState(() => _isCapturing = false);
      _showLimit();
    } catch (_) {
      setState(() => _isCapturing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).captureFailed)),
      );
    }
  }

  Future<void> _import() async {
    try {
      final images = await AppScope.of(context).gallery.pickImages();
      if (images.isEmpty || !mounted) return;
      await _camera?.stopImageStream();
      for (final bytes in images) {
        await _session.addBytes(bytes, manual: _manual);
      }
      if (!mounted) return;
      await _camera?.dispose();
      setState(() {
        _camera = null;
        _editing = true;
        _liveQuad = null;
      });
    } on StateError {
      _showLimit();
      if (_session.pages.isNotEmpty && mounted) {
        setState(() => _editing = true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).importFailed)),
      );
    }
  }

  void _showLimit() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.pageLimitReached(_session.maxPages))),
      );
  }

  Future<void> _toggleFlash() async {
    final next = !_flash;
    await _camera?.setFlash(next);
    if (mounted) setState(() => _flash = next);
  }

  /// "Scan another page": reopen the camera; the next capture is appended.
  Future<void> _addPage() async {
    if (!_session.canAddPage) {
      _showLimit();
      return;
    }
    setState(() => _editing = false);
    await _openCamera();
  }

  /// Leaves the camera without capturing and returns to the pages already
  /// scanned (instead of offering to discard the whole scan).
  Future<void> _backToPages() async {
    final camera = _camera;
    if (camera != null) {
      if (_flash) await camera.setFlash(false);
      await camera.stopImageStream();
      await camera.dispose();
    }
    if (!mounted) return;
    setState(() {
      _camera = null;
      _editing = true;
      _flash = false;
      _isCapturing = false;
      _liveQuad = null;
    });
  }

  void _closeCamera() {
    if (_session.pages.isNotEmpty) {
      _backToPages();
    } else {
      _maybeLeave();
    }
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    if (_session.pages.isEmpty) return;
    final target = widget.appendTo;
    if (target != null) {
      await _finishAppend(target);
      return;
    }
    final saved = await _askToSave();
    if (saved == null || !mounted) return;
    final documents = AppScope.of(context).documents;
    final navigator = Navigator.of(context);
    unawaited(showBusyDialog(context, l10n.processing));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    try {
      await _session.commitPending();
      if (!mounted) return;
      final document = await documents.createDocument(
        name: saved.name,
        folderId: saved.folderId,
        pages: [
          for (final page in _session.pages)
            NewPage(
              id: page.id,
              originalJpeg: page.originalJpeg,
              processedJpeg: page.previewJpeg,
              filter: page.filter,
              corners: page.corners,
            ),
        ],
      );
      if (!mounted) return;
      navigator.pop();
      navigator.pop();
      await navigator.pushNamed('/document', arguments: document);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.couldNotSave)));
    }
  }

  /// Adds the new pages to the end of [target] and pops with their count.
  Future<void> _finishAppend(ScanAppendTarget target) async {
    final l10n = AppLocalizations.of(context);
    final documents = AppScope.of(context).documents;
    final navigator = Navigator.of(context);
    unawaited(
      showBusyDialog(context, l10n.addingToDocument(target.document.name)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    try {
      // Match the size of the pages already in the document so the PDF
      // stays uniform.
      final existing = await documents.pagesFor(target.document.id);
      if (existing.isNotEmpty) {
        final bytes = await File(existing.first.processedPath).readAsBytes();
        final info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info != null && info.width > 0 && info.height > 0) {
          _session.forceWidth = info.width;
          _session.forceHeight = info.height;
        }
      }
      await _session.commitPending();
      if (!mounted) return;
      final added = await documents.appendPages(target.document.id, [
        for (final page in _session.pages)
          NewPage(
            id: page.id,
            originalJpeg: page.originalJpeg,
            processedJpeg: page.previewJpeg,
            filter: page.filter,
            corners: page.corners,
          ),
      ]);
      if (!mounted) return;
      navigator.pop();
      navigator.pop(added.length);
    } on StateError {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showLimit();
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.couldNotSave)));
    }
  }

  Future<({String name, String? folderId})?> _askToSave() async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(
      text: defaultDocumentName(DateTime.now()),
    );
    var folderValue = widget.folderId ?? '';
    final folders = AppScope.of(context).library.folders;
    final result = await showDialog<({String name, String? folderId})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(l10n.saveDocument),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(labelText: l10n.documentName),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: folderValue,
                    decoration: InputDecoration(labelText: l10n.chooseFolder),
                    items: [
                      DropdownMenuItem(value: '', child: Text(l10n.noFolder)),
                      for (final folder in folders)
                        DropdownMenuItem(
                          value: folder.id,
                          child: Text(folder.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocal(() => folderValue = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(context, (
                      name: name,
                      folderId: folderValue.isEmpty ? null : folderValue,
                    ));
                  },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
    return result;
  }

  Future<void> _maybeLeave() async {
    if (_session.pages.isEmpty) {
      _leave();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final discard = await confirmAction(
      context,
      title: l10n.discardScanTitle,
      message: l10n.discardScanBody,
      confirm: l10n.discard,
    );
    if (discard && mounted) _leave();
  }

  void _leave() {
    _camera?.setFlash(false);
    _camera?.stopImageStream();
    setState(() => _forcePop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = widget.appendTo;
    return PopScope(
      canPop: _forcePop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_editing && _session.pages.isNotEmpty) {
          _backToPages();
        } else {
          _maybeLeave();
        }
      },
      child: _editing
          ? PageEditor(
              session: _session,
              onAddPage: _addPage,
              onDone: _finish,
              doneLabel: target == null ? null : l10n.addToDocument,
              banner: target == null
                  ? null
                  : l10n.addingToDocument(target.document.name),
            )
          : CameraStage(
              camera: _camera,
              status: _status,
              flashOn: _flash,
              hasTorch: _camera?.hasTorch ?? false,
              manual: _manual,
              detectedQuad: _liveQuad,
              isCapturing: _isCapturing,
              pageCount: _session.totalPages,
              closeLabel: _session.pages.isNotEmpty ? l10n.backToPages : null,
              onCapture: _capture,
              onGallery: _import,
              onFlash: _toggleFlash,
              onRetry: _openCamera,
              onClose: _closeCamera,
              onManualChanged: (manual) => setState(() => _manual = manual),
            ),
    );
  }
}
