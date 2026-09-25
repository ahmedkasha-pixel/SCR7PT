import 'drive_models.dart';

/// The Drive calls the queue needs. Production uses [GoogleDriveGateway].
abstract class DriveGateway {
  Future<DriveAccount?> restore();

  Future<DriveAccount> signIn();

  Future<void> signOut();

  /// Uploads [parts]. When [existingFileIds] is non-empty, those files are
  /// updated in order instead of creating duplicates. Extra old files are
  /// removed. Returns the file ids that now represent the document.
  Future<List<String>> upload({
    required List<DrivePart> parts,
    required List<String> existingFileIds,
    required String? subfolder,
    required Future<void> Function(double progress) onProgress,
  });
}
