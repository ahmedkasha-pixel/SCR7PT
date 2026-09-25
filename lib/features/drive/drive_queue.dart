import '../../data/models/records.dart';
import 'drive_gateway.dart';
import 'drive_models.dart';
import 'drive_store.dart';

typedef DriveExporter = Future<DrivePayload> Function(DriveLink link);

/// Decides when a document may upload, and keeps one Drive file identity.
class DriveQueue {
  DriveQueue({
    required this.store,
    required this.gateway,
    required this.export,
    this.onChanged,
    this.wifiOnly = false,
    this.network = NetworkSnapshot.onWifi,
  });

  final DriveLinkStore store;
  final DriveGateway gateway;
  final DriveExporter export;
  void Function()? onChanged;
  bool wifiOnly;
  NetworkSnapshot network;

  bool _busy = false;

  bool get _canSend => network.online && (!wifiOnly || network.wifi);

  Future<void> enqueue({
    required String documentId,
    required ShareFormat format,
    required CompressionLevel compression,
  }) async {
    final existing = await store.get(documentId);
    await store.put(
      DriveLink(
        documentId: documentId,
        status: DriveSyncStatus.queued,
        fileIds: existing?.fileIds ?? const [],
        format: format,
        compression: compression,
        updatedAt: DateTime.now(),
      ),
    );
    onChanged?.call();
    await pump();
  }

  Future<void> retry(String documentId) async {
    final existing = await store.get(documentId);
    if (existing == null) return;
    await store.put(
      existing.copy(
        status: DriveSyncStatus.queued,
        progress: 0,
        clearError: true,
        updatedAt: DateTime.now(),
      ),
    );
    onChanged?.call();
    await pump();
  }

  Future<void> pump() async {
    if (_busy) return;
    _busy = true;
    try {
      await store.normalizeInterrupted();
      while (_canSend) {
        final next = await store.nextQueued();
        if (next == null) return;
        await _run(next);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _run(DriveLink link) async {
    final startedAt = link.updatedAt;
    await store.put(
      link.copy(status: DriveSyncStatus.uploading, progress: 0, clearError: true),
    );
    onChanged?.call();
    try {
      final payload = await export(link);
      if (payload.parts.isEmpty) {
        throw StateError('empty');
      }
      final ids = await gateway.upload(
        parts: payload.parts,
        existingFileIds: link.fileIds,
        subfolder: payload.subfolder,
        onProgress: (progress) async {
          await store.saveProgress(
            link.documentId,
            startedAt,
            progress.clamp(0, 1),
          );
          onChanged?.call();
        },
      );
      final current = await store.get(link.documentId);
      if (current == null || current.updatedAt != startedAt) return;
      await store.put(
        current.copy(
          status: DriveSyncStatus.uploaded,
          fileIds: ids,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      final current = await store.get(link.documentId);
      if (current == null || current.updatedAt != startedAt) return;
      await store.put(
        current.copy(
          status: DriveSyncStatus.failed,
          progress: 0,
          error: '$error',
        ),
      );
    }
    onChanged?.call();
  }
}
