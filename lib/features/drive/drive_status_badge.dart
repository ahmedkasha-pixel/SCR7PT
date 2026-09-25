import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'drive_models.dart';

class DriveStatusBadge extends StatelessWidget {
  const DriveStatusBadge({super.key, required this.link, this.onRetry});

  final DriveLink? link;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = link?.status;
    final (icon, label, color) = switch (status) {
      null => (Icons.cloud_off_outlined, l10n.driveStatusNone, Colors.white70),
      DriveSyncStatus.queued => (
        Icons.schedule,
        l10n.driveStatusQueued,
        const Color(0xFFFBBF24),
      ),
      DriveSyncStatus.uploading => (
        Icons.cloud_upload_outlined,
        l10n.driveStatusUploading,
        const Color(0xFF60A5FA),
      ),
      DriveSyncStatus.uploaded => (
        Icons.cloud_done_outlined,
        l10n.driveStatusUploaded,
        const Color(0xFF34D399),
      ),
      DriveSyncStatus.failed => (
        Icons.error_outline,
        l10n.driveStatusFailed,
        const Color(0xFFF87171),
      ),
    };
    return Wrap(
      key: const Key('drive-status'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Icon(icon, size: 18, color: color),
        Text(label, style: TextStyle(color: color)),
        if (status == DriveSyncStatus.uploading)
          SizedBox(
            width: 88,
            child: LinearProgressIndicator(
              value: (link?.progress ?? 0).clamp(0, 1),
            ),
          ),
        if (status == DriveSyncStatus.failed)
          TextButton(
            key: const Key('drive-retry'),
            onPressed: onRetry,
            child: Text(l10n.driveRetry),
          ),
      ],
    );
  }
}
