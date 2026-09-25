/// Phase 3 slot. Google Drive is the first target; the interface stays
/// generic so another provider can be added without rewriting documents.
abstract class CloudStorage {
  String get id;

  Future<void> signIn();

  Future<void> signOut();

  Future<void> uploadDocument(String documentId);
}

class GoogleDriveStorage implements CloudStorage {
  @override
  String get id => 'google_drive';

  @override
  Future<void> signIn() => _pending();

  @override
  Future<void> signOut() => _pending();

  @override
  Future<void> uploadDocument(String documentId) => _pending();

  Future<void> _pending() {
    throw UnimplementedError(
      'Google Drive upload is planned for phase 3 and is not available yet.',
    );
  }
}
