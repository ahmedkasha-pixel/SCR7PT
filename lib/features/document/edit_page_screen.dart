import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import '../scan/page_editor.dart';
import '../scan/scan_session.dart';

class EditPageScreen extends StatefulWidget {
  const EditPageScreen({super.key, required this.page});

  final PageRecord page;

  @override
  State<EditPageScreen> createState() => _EditPageScreenState();
}

class _EditPageScreenState extends State<EditPageScreen> {
  ScanSession? _session;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final original = await File(widget.page.originalPath).readAsBytes();
      final preview = await File(widget.page.processedPath).readAsBytes();
      final decoded = img.decodeImage(original);
      if (decoded == null) throw const FormatException('unsupported-image');
      final session = ScanSession();
      session.pages.add(
        EditablePage(
          id: widget.page.id,
          originalJpeg: original,
          previewJpeg: preview,
          corners: widget.page.corners,
          width: decoded.width,
          height: decoded.height,
          filter: widget.page.filter,
          cropping: false,
        ),
      );
      if (!mounted) return;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final session = _session;
    final l10n = AppLocalizations.of(context);
    if (session == null || session.pages.isEmpty) return;
    final documents = AppScope.of(context).documents;
    final navigator = Navigator.of(context);
    unawaited(showBusyDialog(context, l10n.processing));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    try {
      await session.commitPending();
      if (!mounted) return;
      final page = session.current!;
      await documents.updatePage(
        pageId: widget.page.id,
        filter: page.filter,
        corners: page.corners,
        processedJpeg: page.previewJpeg,
      );
      if (!mounted) return;
      navigator.pop();
      navigator.pop();
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.couldNotSave)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = _session;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.importFailed)),
      );
    }
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PageEditor(
      session: session,
      showAdd: false,
      onAddPage: null,
      onDone: _save,
    );
  }
}
