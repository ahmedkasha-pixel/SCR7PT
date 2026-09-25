import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../data/models/records.dart';
import '../l10n/app_localizations.dart';
import 'dialogs.dart';

Future<void> shareDocument(
  BuildContext context,
  DocumentRecord document,
) async {
  final l10n = AppLocalizations.of(context);
  final scope = AppScope.of(context);
  final pages = await scope.documents.pagesFor(document.id);
  if (!context.mounted) return;
  if (pages.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.nothingToShare)));
    return;
  }

  final format = await showModalBottomSheet<ShareFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) =>
        _ShareSheet(initial: scope.settings.settings.shareFormat),
  );
  if (format == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  unawaited(showBusyDialog(context, l10n.preparingShare));
  try {
    await scope.sharer.shareDocument(
      document: document,
      pages: pages,
      format: format,
      origin: origin,
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.initial});

  final ShareFormat initial;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late ShareFormat _format = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.shareAs, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            RadioGroup<ShareFormat>(
              groupValue: _format,
              onChanged: (value) {
                if (value != null) setState(() => _format = value);
              },
              child: Column(
                children: [
                  RadioListTile<ShareFormat>(
                    value: ShareFormat.pdf,
                    title: Text(l10n.sharePdf),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<ShareFormat>(
                    value: ShareFormat.jpg,
                    title: Text(l10n.shareJpg),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _format),
              icon: const Icon(Icons.ios_share),
              label: Text(l10n.share),
            ),
          ],
        ),
      ),
    );
  }
}
