import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/document_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/share_sheet.dart';
import '../home/home_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.folder, this.initialDocuments});

  final FolderRecord folder;

  /// Skips the database read on the first frame when documents are already known.
  final List<DocumentRecord>? initialDocuments;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  late String _name = widget.folder.name;
  List<DocumentRecord> _documents = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialDocuments;
    if (seeded != null) {
      _documents = seeded;
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final documents = await AppScope.of(context).documents
        .listDocuments(folderId: widget.folder.id);
    if (!mounted) return;
    setState(() {
      _documents = documents;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _rename();
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
              PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(
            context,
            '/scan',
            arguments: widget.folder.id,
          );
          if (mounted) await _load();
        },
        icon: const Icon(Icons.document_scanner_outlined),
        label: Text(l10n.scan),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.folder_open,
                title: l10n.emptyFolderTitle,
                body: l10n.emptyFolderBody,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              itemCount: _documents.length,
              itemBuilder: (context, index) {
                final document = _documents[index];
                return DocumentCard(
                  document: document,
                  onOpen: () async {
                    await Navigator.pushNamed(
                      context,
                      '/document',
                      arguments: document,
                    );
                    if (mounted) await _load();
                  },
                  onRename: () => _renameDocument(document),
                  onMove: () => _moveDocument(document),
                  onShare: () => shareDocument(context, document),
                  onDelete: () => _deleteDocument(document),
                );
              },
            ),
    );
  }

  Future<void> _rename() async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForName(
      context,
      title: l10n.renameFolder,
      label: l10n.folderName,
      initial: _name,
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).documents.renameFolder(widget.folder.id, name);
    if (mounted) setState(() => _name = name);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmAction(
      context,
      title: l10n.deleteFolderTitle,
      message: l10n.deleteFolderBody,
      confirm: l10n.delete,
    );
    if (!ok || !mounted) return;
    await AppScope.of(context).documents.deleteFolder(widget.folder.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _renameDocument(DocumentRecord document) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForName(
      context,
      title: l10n.renameDocument,
      label: l10n.documentName,
      initial: document.name,
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).documents.renameDocument(document.id, name);
    await _load();
  }

  Future<void> _moveDocument(DocumentRecord document) async {
    final choice = await showFolderPicker(context, selected: document.folderId);
    if (!mounted || choice == null) return;
    await AppScope.of(context).documents.moveDocument(
      document.id,
      choice == folderPickerRoot ? null : choice as String,
    );
    await _load();
  }

  Future<void> _deleteDocument(DocumentRecord document) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmAction(
      context,
      title: l10n.deleteDocumentTitle,
      message: l10n.deleteDocumentBody,
      confirm: l10n.delete,
    );
    if (!ok || !mounted) return;
    await AppScope.of(context).documents.deleteDocument(document.id);
    await _load();
  }
}
