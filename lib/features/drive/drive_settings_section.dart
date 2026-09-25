import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../l10n/app_localizations.dart';
import 'drive_models.dart';
import 'drive_sign_in_error.dart';

class DriveSettingsSection extends StatelessWidget {
  const DriveSettingsSection({super.key, this.showDeveloperHint = false});

  /// File-path hint for debug builds. Release screens leave this off.
  final bool showDeveloperHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final drive = AppScope.of(context).drive;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: drive,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.cloudTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!drive.configured)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.driveNotSetUpTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.driveNotSetUpBody),
                      if (showDeveloperHint) ...[
                        const SizedBox(height: 8),
                        Text(
                          l10n.driveNotSetUpDebug,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _account(context, l10n, drive.account, drive.signingIn),
                ),
              ),
              SwitchListTile(
                key: const Key('drive-auto-upload'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.driveAutoUpload),
                value: drive.autoUpload,
                onChanged: drive.account == null
                    ? null
                    : (value) => drive.setAutoUpload(value),
              ),
              SwitchListTile(
                key: const Key('drive-wifi-only'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.driveWifiOnly),
                value: drive.wifiOnly,
                onChanged: drive.account == null
                    ? null
                    : (value) => drive.setWifiOnly(value),
              ),
              Text(
                l10n.driveFolderHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _account(
    BuildContext context,
    AppLocalizations l10n,
    DriveAccount? account,
    bool signingIn,
  ) {
    final drive = AppScope.of(context).drive;
    if (account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.driveSignedOut),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('drive-sign-in'),
            onPressed: signingIn ? null : () => _signIn(context),
            icon: signingIn
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(l10n.driveSignIn),
          ),
        ],
      );
    }
    final photo = account.photoUrl;
    return Row(
      children: [
        CircleAvatar(
          backgroundImage: photo == null ? null : NetworkImage(photo),
          child: photo == null ? Text(account.initial) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.displayName ?? account.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                account.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        TextButton(
          key: const Key('drive-sign-out'),
          onPressed: drive.signOut,
          child: Text(l10n.driveSignOut),
        ),
      ],
    );
  }

  Future<void> _signIn(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      await AppScope.of(context).drive.signIn();
    } catch (error) {
      if (!context.mounted) return;
      final report = describeDriveSignInError(error);
      if (report.problem == DriveSignInProblem.canceled) return;
      final message = switch (report.problem) {
        DriveSignInProblem.developerError => l10n.driveSignInDeveloperError,
        DriveSignInProblem.wrongClient => l10n.driveSignInWrongClient,
        DriveSignInProblem.testUser => l10n.driveSignInTestUser,
        DriveSignInProblem.other => l10n.driveSignInFailedDetail(report.detail),
        DriveSignInProblem.canceled => l10n.driveSignInFailed,
      };
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.driveSignInFailed),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
    }
  }
}
