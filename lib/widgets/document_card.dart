import 'dart:io';

import 'package:flutter/material.dart';

import '../core/naming/document_name.dart';
import '../core/theme/app_theme.dart';
import '../data/models/records.dart';
import '../l10n/app_localizations.dart';

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.onOpen,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
    this.snippet,
    this.highlightStart = 0,
    this.highlightEnd = 0,
    this.pageLabel,
  });

  final DocumentRecord document;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final String? snippet;
  final int highlightStart;
  final int highlightEnd;
  final String? pageLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              _Cover(path: document.coverPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatTimestamp(document.updatedAt)}   ${l10n.pagesCount(document.pageCount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (snippet != null && snippet!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _SnippetText(
                        text: snippet!,
                        highlightStart: highlightStart,
                        highlightEnd: highlightEnd,
                      ),
                    ],
                    if (pageLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        pageLabel!,
                        key: const Key('search-page'),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.accent),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l10n.moreActions,
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename();
                    case 'move':
                      onMove();
                    case 'share':
                      onShare();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                  PopupMenuItem(value: 'move', child: Text(l10n.move)),
                  PopupMenuItem(value: 'share', child: Text(l10n.share)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnippetText extends StatelessWidget {
  const _SnippetText({
    required this.text,
    required this.highlightStart,
    required this.highlightEnd,
  });

  final String text;
  final int highlightStart;
  final int highlightEnd;

  @override
  Widget build(BuildContext context) {
    final end = highlightEnd.clamp(0, text.length);
    final start = highlightStart.clamp(0, end);
    final style = Theme.of(context).textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: style?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              backgroundColor: AppColors.accent.withValues(alpha: 0.18),
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      key: const Key('search-snippet'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = path == null ? null : File(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 68,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: scheme.secondaryContainer,
                child: Icon(
                  Icons.description_outlined,
                  color: scheme.onSecondaryContainer,
                ),
              ),
      ),
    );
  }
}
