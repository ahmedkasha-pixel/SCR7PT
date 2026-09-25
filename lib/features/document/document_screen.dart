import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/share_sheet.dart';
import '../home/home_screen.dart';
import 'edit_page_screen.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.document, this.initialPages});

  final DocumentRecord document;

  /// Skips the database read on the first frame when pages are already known.
  final List<PageRecord>? initialPages;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late DocumentRecord _document = widget.document;
  List<PageRecord> _pages = const [];
  int _index = 0;
  bool _loading = true;
  final _controller = PageController();

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialPages;
    if (seeded != null) {
      _pages = seeded;
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    final document = await scope.documents.documentById(widget.document.id);
    final pages = await scope.documents.pagesFor(widget.document.id);
    if (!mounted) return;
    if (document == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _document = document;
      _pages = pages;
      if (_index >= pages.length) _index = pages.isEmpty ? 0 : pages.length - 1;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: l10n.editPage,
            onPressed: _pages.isEmpty ? null : _edit,
            icon: const Icon(Icons.crop),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _rename();
                case 'move':
                  _move();
                case 'reorder':
                  _reorder();
                case 'delete-page':
                  _deletePage();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
              PopupMenuItem(value: 'move', child: Text(l10n.move)),
              PopupMenuItem(value: 'reorder', child: Text(l10n.reorderPages)),
              if (_pages.length > 1)
                PopupMenuItem(
                  value: 'delete-page',
                  child: Text(l10n.deletePage),
                ),
              PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: InteractiveViewer(
                          child: Image.file(
                            File(_pages[index].processedPath),
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_pages.isNotEmpty)
                  Text(l10n.pagePosition(_index + 1, _pages.length)),
                SizedBox(
                  height: 84,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final selected = index == _index;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: InkWell(
                          onTap: () {
                            _controller.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Image.file(
                              File(_pages[index].processedPath),
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _rename,
                            icon: const Icon(Icons.drive_file_rename_outline),
                            label: Text(l10n.rename),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('document-share'),
                            onPressed: () => shareDocument(context, _document),
                            icon: const Icon(Icons.ios_share),
                            label: Text(l10n.share),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _edit() async {
    final removed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditPageScreen(page: _pages[_index])),
    );
    if (removed == true && mounted) {
      Navigator.pop(context);
      return;
    }
    await _load();
  }

  Future<void> _rename() async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForName(
      context,
      title: l10n.renameDocument,
      label: l10n.documentName,
      initial: _document.name,
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).documents.renameDocument(_document.id, name);
    await _load();
  }

  Future<void> _move() async {
    final choice = await showFolderPicker(
      context,
      selected: _document.folderId,
    );
    if (!mounted || choice == null) return;
    await AppScope.of(context).documents.moveDocument(
      _document.id,
      choice == folderPickerRoot ? null : choice as String,
    );
    await _load();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmAction(
      context,
      title: l10n.deleteDocumentTitle,
      message: l10n.deleteDocumentBody,
      confirm: l10n.delete,
    );
    if (!ok || !mounted) return;
    await AppScope.of(context).documents.deleteDocument(_document.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deletePage() async {
    if (_pages.length <= 1) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmAction(
      context,
      title: l10n.deletePage,
      message: l10n.deleteDocumentBody,
      confirm: l10n.delete,
    );
    if (!ok || !mounted) return;
    await AppScope.of(context).documents.deletePage(_pages[_index].id);
    await _load();
  }

  Future<void> _reorder() async {
    if (_pages.length < 2) return;
    final ordered = [..._pages];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final l10n = AppLocalizations.of(context);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.5,
                child: ReorderableListView.builder(
                  itemCount: ordered.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setLocal(() {
                      final page = ordered.removeAt(oldIndex);
                      ordered.insert(newIndex, page);
                    });
                  },
                  itemBuilder: (context, index) => ListTile(
                    key: ValueKey(ordered[index].id),
                    title: Text(l10n.pagePosition(index + 1, ordered.length)),
                    subtitle: Text(ordered[index].filter.name),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    await AppScope.of(context).documents
        .reorderPages(_document.id, [for (final page in ordered) page.id]);
    await _load();
  }
}
