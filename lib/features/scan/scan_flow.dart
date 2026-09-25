import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/app_config.dart';
import '../../core/naming/document_name.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import 'camera_stage.dart';
import 'page_editor.dart';
import 'scan_camera.dart';
import 'scan_session.dart';

class ScanFlow extends StatefulWidget {
  const ScanFlow({super.key, this.folderId});

  final String? folderId;

  @override
  State<ScanFlow> createState() => _ScanFlowState();
}

class _ScanFlowState extends State<ScanFlow> {
  late final ScanSession _session = ScanSession(folderId: widget.folderId);
  ScanCamera? _camera;
  ScanCameraStatus? _status;
  bool _editing = false;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
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
    if (!mounted) {
      await camera.dispose();
      return;
    }
    setState(() {
      _camera = camera;
      _status = status;
    });
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      final bytes = await camera.takePicture();
      await _session.addBytes(bytes);
      if (!mounted) return;
      await _camera?.dispose();
      setState(() {
        _camera = null;
        _editing = true;
      });
    } on StateError {
      _showLimit();
    } catch (_) {
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
      for (final bytes in images) {
        await _session.addBytes(bytes);
      }
      if (!mounted) return;
      await _camera?.dispose();
      setState(() {
        _camera = null;
        _editing = true;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.pageLimit(AppConfig.maxPagesPerDocument))),
    );
  }

  Future<void> _toggleFlash() async {
    final next = !_flash;
    await _camera?.setFlash(next);
    if (mounted) setState(() => _flash = next);
  }

  Future<void> _addPage() async {
    setState(() => _editing = false);
    await _openCamera();
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    if (_session.pages.isEmpty) return;
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
      Navigator.pop(context);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final discard = await confirmAction(
      context,
      title: l10n.discardScanTitle,
      message: l10n.discardScanBody,
      confirm: l10n.discard,
    );
    if (discard && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeLeave();
      },
      child: _editing
          ? PageEditor(session: _session, onAddPage: _addPage, onDone: _finish)
          : CameraStage(
              camera: _camera,
              status: _status,
              flashOn: _flash,
              onCapture: _capture,
              onGallery: _import,
              onFlash: _toggleFlash,
              onRetry: _openCamera,
            ),
    );
  }
}
