import 'package:flutter/material.dart';

import '../../data/models/records.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/crop_overlay.dart';
import 'scan_session.dart';

class PageEditor extends StatelessWidget {
  const PageEditor({
    super.key,
    required this.session,
    required this.onAddPage,
    required this.onDone,
    this.showAdd = true,
  });

  final ScanSession session;
  final VoidCallback? onAddPage;
  final Future<void> Function() onDone;
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final page = session.current;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              page == null
                  ? l10n.cameraTitle
                  : l10n.pagePosition(session.index + 1, session.pages.length),
            ),
          ),
          body: page == null
              ? const SizedBox.shrink()
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: page.cropping
                                ? CropOverlay(
                                    bytes: page.originalJpeg,
                                    imageWidth: page.width,
                                    imageHeight: page.height,
                                    quad: page.corners,
                                    onChanged: session.updateCorner,
                                  )
                                : Center(
                                    child: Image.memory(
                                      page.previewJpeg,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                          ),
                        ),
                        if (page.cropping)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Text(
                              l10n.cornersHint,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          )
                        else
                          SizedBox(
                            height: 52,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              children: [
                                for (final filter in PageFilter.values)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: ChoiceChip(
                                      key: Key('filter-${filter.name}'),
                                      label: Text(_filterLabel(l10n, filter)),
                                      selected: page.filter == filter,
                                      onSelected: session.busy
                                          ? null
                                          : (_) => session.setFilter(filter),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        SizedBox(
                          height: 84,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: session.pages.length,
                            itemBuilder: (context, index) {
                              final item = session.pages[index];
                              final selected = index == session.index;
                              return Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                child: InkWell(
                                  onTap: () => session.select(index),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        item.previewJpeg,
                                        width: 48,
                                        height: 64,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      ),
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
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                if (page.cropping) ...[
                                  OutlinedButton(
                                    onPressed: session.resetCorners,
                                    child: Text(l10n.resetCorners),
                                  ),
                                  FilledButton(
                                    key: const Key('preview-button'),
                                    onPressed: session.busy
                                        ? null
                                        : session.applyCrop,
                                    child: Text(l10n.preview),
                                  ),
                                ] else
                                  OutlinedButton(
                                    key: const Key('adjust-crop'),
                                    onPressed: session.beginCrop,
                                    child: Text(l10n.adjustCrop),
                                  ),
                                OutlinedButton(
                                  onPressed: () => _reorder(context),
                                  child: Text(l10n.reorderPages),
                                ),
                                if (showAdd)
                                  OutlinedButton(
                                    onPressed: () => _delete(context),
                                    child: Text(l10n.deletePage),
                                  ),
                                if (showAdd)
                                  OutlinedButton.icon(
                                    key: const Key('add-page'),
                                    onPressed: onAddPage,
                                    icon: const Icon(Icons.add),
                                    label: Text(l10n.addPage),
                                  ),
                                FilledButton.icon(
                                  key: const Key('done-button'),
                                  onPressed: session.busy
                                      ? null
                                      : () => onDone(),
                                  icon: const Icon(Icons.check),
                                  label: Text(showAdd ? l10n.done : l10n.save),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (session.busy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    if (session.pages.length <= 1) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.removeOnlyPageTitle),
          content: Text(l10n.removeOnlyPageBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      if (discard == true) session.removeAt(session.index);
      return;
    }
    session.removeAt(session.index);
  }

  void _reorder(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ReorderSheet(session: session),
    );
  }
}

class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.session});

  final ScanSession session;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final List<EditablePage> _pages = [...widget.session.pages];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: ReorderableListView.builder(
          itemCount: _pages.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final page = _pages.removeAt(oldIndex);
              _pages.insert(newIndex, page);
            });
            widget.session.movePage(oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final page = _pages[index];
            return ListTile(
              key: ValueKey(page.id),
              leading: Image.memory(
                page.previewJpeg,
                width: 40,
                height: 52,
                fit: BoxFit.cover,
              ),
              title: Text(l10n.pagePosition(index + 1, _pages.length)),
            );
          },
        ),
      ),
    );
  }
}

String _filterLabel(AppLocalizations l10n, PageFilter filter) {
  switch (filter) {
    case PageFilter.original:
      return l10n.filterOriginal;
    case PageFilter.grayscale:
      return l10n.filterGrayscale;
    case PageFilter.blackAndWhite:
      return l10n.filterBlackAndWhite;
    case PageFilter.brighten:
      return l10n.filterBrighten;
  }
}
