import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../features/drive/drive_controller.dart';
import '../../l10n/app_localizations.dart';
import '../drive/drive_settings_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.showDriveDeveloperHint = kDebugMode});

  /// Debug builds show where to paste the Web client ID. Release builds do not.
  final bool showDriveDeveloperHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final drive = scope.drive;
    final library = scope.library;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, drive, library]),
        builder: (context, _) {
          final current = settings.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(l10n.theme, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('theme-dark'),
                    label: Text(l10n.themeDark),
                    selected: current.appearance == AppAppearance.dark,
                    onSelected: (_) =>
                        settings.setAppearance(AppAppearance.dark),
                  ),
                  ChoiceChip(
                    key: const Key('theme-light'),
                    label: Text(l10n.themeLight),
                    selected: current.appearance == AppAppearance.light,
                    onSelected: (_) =>
                        settings.setAppearance(AppAppearance.light),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.language,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('lang-system'),
                    label: Text(l10n.languageSystem),
                    selected: current.languageCode == null,
                    onSelected: (_) => settings.setLanguage(null),
                  ),
                  ChoiceChip(
                    key: const Key('lang-ar'),
                    label: Text(l10n.languageArabic),
                    selected: current.languageCode == 'ar',
                    onSelected: (_) => settings.setLanguage('ar'),
                  ),
                  ChoiceChip(
                    key: const Key('lang-en'),
                    label: Text(l10n.languageEnglish),
                    selected: current.languageCode == 'en',
                    onSelected: (_) => settings.setLanguage('en'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.defaultShareFormat,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('share-pdf'),
                    label: Text(l10n.sharePdf),
                    selected: current.shareFormat == ShareFormat.pdf,
                    onSelected: (_) => settings.setShareFormat(ShareFormat.pdf),
                  ),
                  ChoiceChip(
                    key: const Key('share-jpg'),
                    label: Text(l10n.shareJpg),
                    selected: current.shareFormat == ShareFormat.jpg,
                    onSelected: (_) => settings.setShareFormat(ShareFormat.jpg),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l10n.pageSize,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in PageSizeMode.values)
                    ChoiceChip(
                      key: Key('page-size-${mode.name}'),
                      label: Text(_pageSizeLabel(l10n, mode)),
                      selected: current.pageSizeMode == mode,
                      onSelected: (_) => settings.setPageSizeMode(mode),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  key: const Key('open-signatures'),
                  leading: const Icon(Icons.draw_outlined),
                  title: Text(l10n.signatureTitle),
                  subtitle: Text(l10n.signatureBody),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/signatures'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  key: const Key('reindex-search'),
                  leading: const Icon(Icons.manage_search_outlined),
                  title: Text(l10n.reindexSearch),
                  subtitle: Text(
                    library.indexingTotal > 0
                        ? l10n.searchIndexingProgress(
                            library.indexingCurrent,
                            library.indexingTotal,
                          )
                        : l10n.reindexSearchSubtitle,
                  ),
                  trailing: library.indexingTotal > 0
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: library.indexingTotal > 0
                      ? null
                      : () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.reindexingStarted)),
                          );
                          await scope.documents.clearAllPageText();
                          final pages = await scope.documents.pagesWithoutText();
                          scope.documents.onPagesReady?.call(pages);
                        },
                ),
              ),
              const SizedBox(height: 28),
              DriveSettingsSection(
                showDeveloperHint: showDriveDeveloperHint,
              ),
              const SizedBox(height: 24),
              Text(
                _storageNote(l10n, drive),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _storageNote(AppLocalizations l10n, DriveController drive) {
    if (drive.account == null) return l10n.storageNote;
    if (drive.autoUpload) return l10n.storageNoteCloudAuto;
    return l10n.storageNoteCloud;
  }

  String _pageSizeLabel(AppLocalizations l10n, PageSizeMode mode) {
    switch (mode) {
      case PageSizeMode.auto:
        return l10n.pageSizeAuto;
      case PageSizeMode.a4:
        return l10n.pageSizeA4;
      case PageSizeMode.letter:
        return l10n.pageSizeLetter;
      case PageSizeMode.original:
        return l10n.pageSizeOriginal;
    }
  }

}
