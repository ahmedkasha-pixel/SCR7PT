import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../core/processing/compress.dart';
import '../data/models/records.dart';
import '../features/drive/drive_models.dart';
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

  unawaited(showBusyDialog(context, l10n.preparingShare));
  ExportSizes? sizes;
  try {
    sizes = await scope.sharer.measure(document: document, pages: pages);
  } catch (_) {
    sizes = null;
  }
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
  if (!context.mounted) return;

  final choice = await showModalBottomSheet<ShareChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => ShareFormatSheet(
      initial: scope.settings.settings.shareFormat,
      initialLevel: scope.settings.settings.compression,
      sizes: sizes,
    ),
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  await scope.settings.setCompression(choice.level);
  if (choice.toDrive) {
    final result = await scope.drive.saveDocument(
      document.id,
      format: choice.format,
      compression: choice.level,
    );
    if (!context.mounted) return;
    final message = switch (result) {
      DriveSaveResult.queued => l10n.driveQueued,
      DriveSaveResult.notConfigured => l10n.driveNotSetUpTitle,
      DriveSaveResult.needsSignIn => l10n.driveNeedsSignIn,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  unawaited(showBusyDialog(context, l10n.preparingShare));
  try {
    await scope.sharer.shareDocument(
      document: document,
      pages: pages,
      format: choice.format,
      compression: choice.level,
      origin: origin,
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

typedef ShareChoice = ({
  ShareFormat format,
  CompressionLevel level,
  bool toDrive,
});

class ShareFormatSheet extends StatefulWidget {
  const ShareFormatSheet({
    super.key,
    required this.initial,
    this.initialLevel = CompressionLevel.medium,
    this.sizes,
  });

  final ShareFormat initial;
  final CompressionLevel initialLevel;
  final ExportSizes? sizes;

  @override
  State<ShareFormatSheet> createState() => _ShareFormatSheetState();
}

class _ShareFormatSheetState extends State<ShareFormatSheet> {
  late ShareFormat _format = widget.initial;
  late CompressionLevel _level = widget.initialLevel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sizes = widget.sizes;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.shareAs, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
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
            Text(l10n.quality, style: Theme.of(context).textTheme.titleMedium),
            if (sizes != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  '${l10n.originalSize} · ${formatByteSize(sizes.original)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            RadioGroup<CompressionLevel>(
              groupValue: _level,
              onChanged: (value) {
                if (value != null) setState(() => _level = value);
              },
              child: Column(
                children: [
                  for (final level in CompressionLevel.values)
                    RadioListTile<CompressionLevel>(
                      key: Key('quality-${level.name}'),
                      value: level,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_qualityLabel(l10n, level)),
                      secondary: sizes == null
                          ? null
                          : Text(
                              formatByteSize(sizes.bytesFor(_format, level)),
                            ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, (
                format: _format,
                level: _level,
                toDrive: false,
              )),
              icon: const Icon(Icons.ios_share),
              label: Text(l10n.share),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('share-save-drive'),
              onPressed: () => Navigator.pop(context, (
                format: _format,
                level: _level,
                toDrive: true,
              )),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(l10n.driveSave),
            ),
          ],
        ),
      ),
    );
  }

  String _qualityLabel(AppLocalizations l10n, CompressionLevel level) {
    switch (level) {
      case CompressionLevel.high:
        return l10n.qualityHigh;
      case CompressionLevel.medium:
        return l10n.qualityMedium;
      case CompressionLevel.low:
        return l10n.qualityLow;
    }
  }
}
