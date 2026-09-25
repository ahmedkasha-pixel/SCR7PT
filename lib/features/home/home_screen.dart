import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/document_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/wordmark.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = AppScope.of(context).library;
      // Widget tests preload the library outside the fake async zone.
      // A second refresh here would open SQLite during a pumped frame.
      if (library.loading) library.refresh();
      Navigator.pushNamed(context, '/scan');
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = AppScope.of(context).library;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            if (library.loading &&
                library.folders.isEmpty &&
                library.recent.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (library.error != null &&
                library.folders.isEmpty &&
                library.recent.isEmpty) {
              return EmptyState(
                icon: Icons.cloud_off_outlined,
                title: l10n.loadError,
                body: l10n.retry,
              );
            }
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Wordmark(size: 26),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tagline,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.homeTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      key: const Key('search-field'),
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: l10n.searchHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(999),
                          ),
                          borderSide: BorderSide(color: scheme.outline),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                          borderSide: BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                        suffixIcon: library.searching
                            ? IconButton(
                                onPressed: () {
                                  _search.clear();
                                  library.setQuery('');
                                },
                                icon: const Icon(Icons.close),
                              )
                            : null,
                      ),
                      onChanged: library.setQuery,
                    ),
                  ),
                ),
                if (library.searching)
                  ..._searchSlivers(context, library.searchResults)
                else ...[
                  SliverToBoxAdapter(
                    child: _sectionTitle(context, l10n.folders),
                  ),
                  SliverToBoxAdapter(child: _folders(context)),
                  SliverToBoxAdapter(
                    child: _sectionTitle(context, l10n.recent),
                  ),
                  if (library.recent.isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyState(
                        key: const Key('empty-home'),
                        icon: Icons.document_scanner_outlined,
                        title: l10n.emptyHomeTitle,
                        body: l10n.emptyHomeBody,
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _card(context, library.recent[index]),
                        childCount: library.recent.length,
                      ),
                    ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _ScanBar(
        onScan: () => _openScan(null),
        onSettings: () async {
          await Navigator.pushNamed(context, '/settings');
          if (context.mounted) await library.refresh();
        },
      ),
    );
  }

  List<Widget> _searchSlivers(
    BuildContext context,
    List<DocumentRecord> results,
  ) {
    final l10n = AppLocalizations.of(context);
    if (results.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.search_off,
            title: l10n.searchResults,
            body: l10n.noSearchResults,
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(child: _sectionTitle(context, l10n.searchResults)),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _card(context, results[index]),
          childCount: results.length,
        ),
      ),
    ];
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _folders(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = AppScope.of(context).library;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: library.folders.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == library.folders.length) {
            return _FolderCard(
              icon: Icons.create_new_folder_outlined,
              title: l10n.newFolder,
              subtitle: '',
              color: scheme.surface,
              onTap: _createFolder,
            );
          }
          final folder = library.folders[index];
          return _FolderCard(
            key: ValueKey('folder-${folder.id}'),
            icon: Icons.folder_outlined,
            title: folder.name,
            subtitle: l10n.documentsCount(folder.documentCount),
            color: scheme.surface,
            onTap: () async {
              await Navigator.pushNamed(context, '/folder', arguments: folder);
              if (context.mounted) await library.refresh();
            },
            onLongPress: () => _folderMenu(folder),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, DocumentRecord document) {
    return DocumentCard(
      key: ValueKey('doc-${document.id}'),
      document: document,
      onOpen: () => _openDocument(document),
      onRename: () => _renameDocument(document),
      onMove: () => _moveDocument(document),
      onShare: () => shareDocument(context, document),
      onDelete: () => _deleteDocument(document),
    );
  }

  Future<void> _openScan(String? folderId) async {
    await Navigator.pushNamed(context, '/scan', arguments: folderId);
    if (mounted) await AppScope.of(context).library.refresh();
  }

  Future<void> _openDocument(DocumentRecord document) async {
    await Navigator.pushNamed(context, '/document', arguments: document);
    if (mounted) await AppScope.of(context).library.refresh();
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForName(
      context,
      title: l10n.newFolder,
      label: l10n.folderName,
      initial: '',
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).documents.createFolder(name);
    if (mounted) await AppScope.of(context).library.refresh();
  }

  Future<void> _folderMenu(FolderRecord folder) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(l10n.rename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await promptForName(
        context,
        title: l10n.renameFolder,
        label: l10n.folderName,
        initial: folder.name,
      );
      if (name == null || !mounted) return;
      await AppScope.of(context).documents.renameFolder(folder.id, name);
    } else if (action == 'delete') {
      final ok = await confirmAction(
        context,
        title: l10n.deleteFolderTitle,
        message: l10n.deleteFolderBody,
        confirm: l10n.delete,
      );
      if (!ok || !mounted) return;
      await AppScope.of(context).documents.deleteFolder(folder.id);
    }
    if (mounted) await AppScope.of(context).library.refresh();
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
    if (mounted) await AppScope.of(context).library.refresh();
  }

  Future<void> _moveDocument(DocumentRecord document) async {
    final choice = await showFolderPicker(context, selected: document.folderId);
    if (!mounted || choice == null) return;
    await AppScope.of(context).documents.moveDocument(
      document.id,
      choice == folderPickerRoot ? null : choice as String,
    );
    if (mounted) await AppScope.of(context).library.refresh();
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
    if (mounted) await AppScope.of(context).library.refresh();
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 148,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanBar extends StatelessWidget {
  const _ScanBar({required this.onScan, required this.onSettings});

  final VoidCallback onScan;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _BarButton(
                        icon: Icons.folder_outlined,
                        label: l10n.homeTitle,
                        selected: true,
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: 72),
                    Expanded(
                      child: _BarButton(
                        key: const Key('settings-button'),
                        icon: Icons.settings_outlined,
                        label: l10n.settings,
                        onPressed: onSettings,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: -18,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: FloatingActionButton(
                      key: const Key('scan-button'),
                      elevation: 2,
                      onPressed: onScan,
                      child: const Icon(Icons.document_scanner_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const folderPickerRoot = '__root__';

Future<Object?> showFolderPicker(
  BuildContext context, {
  required String? selected,
}) {
  final l10n = AppLocalizations.of(context);
  final folders = AppScope.of(context).library.folders;
  return showModalBottomSheet<Object?>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              l10n.moveDocument,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: Text(l10n.noFolder),
            trailing: selected == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, folderPickerRoot),
          ),
          for (final folder in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.name),
              trailing: selected == folder.id ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, folder.id),
            ),
        ],
      ),
    ),
  );
}
