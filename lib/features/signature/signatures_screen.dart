import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/empty_state.dart';
import 'signature_import.dart';

class SignaturesScreen extends StatefulWidget {
  const SignaturesScreen({
    super.key,
    this.selecting = false,
    this.initialItems,
  });

  /// When true, tapping a signature returns it to the previous screen.
  final bool selecting;

  /// Skips the database read when the list is already known (screenshots).
  final List<SignatureRecord>? initialItems;

  @override
  State<SignaturesScreen> createState() => _SignaturesScreenState();
}

class _SignaturesScreenState extends State<SignaturesScreen> {
  late List<SignatureRecord> _items = widget.initialItems ?? const [];
  late bool _loading = widget.initialItems == null;

  @override
  void initState() {
    super.initState();
    if (widget.initialItems == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final items = await AppScope.of(context).signatures.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signatures)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-signature'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l10n.addSignature),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.draw_outlined,
                title: l10n.signatureEmptyTitle,
                body: l10n.signatureEmptyBody,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  child: ListTile(
                    key: Key('signature-${item.id}'),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Checkerboard(
                        child: Image.file(
                          // File is imported below via dart:io in the tile widget.
                          signatureFile(item.imagePath),
                          width: 72,
                          height: 48,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    title: Text(item.name),
                    onTap: widget.selecting
                        ? () => Navigator.pop(context, item)
                        : null,
                    trailing: widget.selecting
                        ? const Icon(Icons.chevron_right)
                        : PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'rename') _rename(item);
                              if (value == 'delete') _delete(item);
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(l10n.rename),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(l10n.delete),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('signature-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.fromCamera),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              key: const Key('signature-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.fromGallery),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              key: const Key('signature-draw'),
              leading: const Icon(Icons.gesture),
              title: Text(l10n.drawSignature),
              onTap: () => Navigator.pop(context, 'draw'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    Uint8List? bytes;
    var cleanupFirst = false;
    if (source == 'camera') {
      bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => const SignatureCameraScreen()),
      );
    } else if (source == 'gallery') {
      final images = await AppScope.of(context).gallery.pickImages();
      if (images.isNotEmpty) bytes = images.first;
    } else {
      bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => const SignatureDrawScreen()),
      );
      cleanupFirst = true;
    }
    if (bytes == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SignatureImportScreen(
          bytes: bytes!,
          startAtCleanup: cleanupFirst,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _rename(SignatureRecord item) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForName(
      context,
      title: l10n.rename,
      label: l10n.signatureName,
      initial: item.name,
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).signatures.rename(item.id, name);
    await _load();
  }

  Future<void> _delete(SignatureRecord item) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmAction(
      context,
      title: l10n.deleteSignatureTitle,
      message: l10n.deleteSignatureBody,
      confirm: l10n.delete,
    );
    if (!ok || !mounted) return;
    await AppScope.of(context).signatures.delete(item.id);
    await _load();
  }
}
