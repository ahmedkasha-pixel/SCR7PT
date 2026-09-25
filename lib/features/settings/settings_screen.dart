import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/records.dart';
import '../../features/upcoming/upcoming_services.dart';
import '../../l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = AppScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListenableBuilder(
        listenable: settings,
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
              const SizedBox(height: 28),
              Text(
                l10n.upcoming,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final entry in UpcomingServices.catalog)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(_icon(entry.kind)),
                    title: Text(_title(l10n, entry.kind)),
                    subtitle: Text(_body(l10n, entry.kind)),
                    trailing: Text(l10n.phaseLabel(entry.phase)),
                    onTap: () {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(l10n.comingSoon)));
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                l10n.storageNote,
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

  IconData _icon(UpcomingKind kind) {
    switch (kind) {
      case UpcomingKind.compression:
        return Icons.compress;
      case UpcomingKind.signature:
        return Icons.draw_outlined;
      case UpcomingKind.googleDrive:
        return Icons.cloud_outlined;
    }
  }

  String _title(AppLocalizations l10n, UpcomingKind kind) {
    switch (kind) {
      case UpcomingKind.compression:
        return l10n.compressionTitle;
      case UpcomingKind.signature:
        return l10n.signatureTitle;
      case UpcomingKind.googleDrive:
        return l10n.cloudTitle;
    }
  }

  String _body(AppLocalizations l10n, UpcomingKind kind) {
    switch (kind) {
      case UpcomingKind.compression:
        return l10n.compressionBody;
      case UpcomingKind.signature:
        return l10n.signatureBody;
      case UpcomingKind.googleDrive:
        return l10n.cloudBody;
    }
  }
}
