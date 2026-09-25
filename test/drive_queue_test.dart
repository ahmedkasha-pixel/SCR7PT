import 'dart:io';
import 'dart:typed_data';

import 'package:docscan/app/settings_controller.dart';
import 'package:docscan/data/db/app_database.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/data/repositories/document_repository.dart';
import 'package:docscan/data/repositories/settings_repository.dart';
import 'package:docscan/data/storage/file_store.dart';
import 'package:docscan/features/share/document_sharer.dart';
import 'package:docscan/features/drive/drive_controller.dart';
import 'package:docscan/features/drive/drive_gateway.dart';
import 'package:docscan/features/drive/drive_models.dart';
import 'package:docscan/features/drive/drive_queue.dart';
import 'package:docscan/features/drive/drive_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sqlite_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureSqlite);

  late MemoryDriveStore store;
  late _FakeGateway gateway;
  late DriveQueue queue;

  setUp(() {
    store = MemoryDriveStore();
    gateway = _FakeGateway();
    queue = DriveQueue(
      store: store,
      gateway: gateway,
      export: (link) async {
        return DrivePayload(
          subfolder: 'عقود',
          parts: [
            DrivePart(
              name: 'عقد.pdf',
              mimeType: 'application/pdf',
              bytes: Uint8List.fromList([1, 2, 3, 4]),
            ),
          ],
        );
      },
    );
  });

  test('offline and mobile-data waits stay queued, then upload on Wi-Fi', () async {
    queue.network = NetworkSnapshot.offline;
    queue.wifiOnly = true;
    await queue.enqueue(
      documentId: 'doc-1',
      format: ShareFormat.pdf,
      compression: CompressionLevel.medium,
    );
    expect((await store.get('doc-1'))!.status, DriveSyncStatus.queued);
    expect(gateway.existingIds, isEmpty);

    queue.network = NetworkSnapshot.mobile;
    await queue.pump();
    expect((await store.get('doc-1'))!.status, DriveSyncStatus.queued);
    expect(gateway.existingIds, isEmpty);

    queue.network = NetworkSnapshot.onWifi;
    await queue.pump();
    final uploaded = (await store.get('doc-1'))!;
    expect(uploaded.status, DriveSyncStatus.uploaded);
    expect(uploaded.fileIds, ['file-1']);
    expect(uploaded.progress, 1);
    expect(gateway.subfolders, ['عقود']);
  });

  test('a second upload updates the same Drive file', () async {
    await queue.enqueue(
      documentId: 'doc-1',
      format: ShareFormat.pdf,
      compression: CompressionLevel.low,
    );
    await queue.enqueue(
      documentId: 'doc-1',
      format: ShareFormat.jpg,
      compression: CompressionLevel.high,
    );
    final link = (await store.get('doc-1'))!;
    expect(link.status, DriveSyncStatus.uploaded);
    expect(link.fileIds, ['file-1']);
    expect(link.format, ShareFormat.jpg);
    expect(gateway.existingIds, [<String>[], ['file-1']]);
  });

  test('a failed upload can be retried', () async {
    gateway.failNext = true;
    await queue.enqueue(
      documentId: 'doc-1',
      format: ShareFormat.pdf,
      compression: CompressionLevel.medium,
    );
    expect((await store.get('doc-1'))!.status, DriveSyncStatus.failed);

    await queue.retry('doc-1');
    final link = (await store.get('doc-1'))!;
    expect(link.status, DriveSyncStatus.uploaded);
    expect(link.fileIds, ['file-1']);
    expect(link.error, isNull);
  });

  test('progress is reported while the upload is running', () async {
    final seen = <double>[];
    queue.onChanged = () {
      final link = store.peek('doc-1');
      if (link != null && link.status == DriveSyncStatus.uploading) {
        seen.add(link.progress);
      }
    };
    gateway.progressSteps = [0.25, 0.8];
    await queue.enqueue(
      documentId: 'doc-1',
      format: ShareFormat.pdf,
      compression: CompressionLevel.medium,
    );
    expect(seen, containsAll([0.25, 0.8]));
    expect((await store.get('doc-1'))!.status, DriveSyncStatus.uploaded);
  });

  test('an interrupted upload is queued again and then sent', () async {
    await store.put(
      DriveLink(
        documentId: 'doc-1',
        status: DriveSyncStatus.uploading,
        progress: 0.4,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await queue.pump();
    expect((await store.get('doc-1'))!.status, DriveSyncStatus.uploaded);
  });

  test('auto-upload stays off until the toggle is on', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController(SettingsRepository());
    await settings.load();
    final local = MemoryDriveStore();
    final fake = _FakeGateway();
    final directory = await Directory.systemTemp.createTemp('drive_auto_');
    final files = FileStore(Directory('${directory.path}/files'));
    final documents = DocumentRepository(
      database: AppDatabase(path: '${directory.path}/db.sqlite'),
      files: files,
    );
    addTearDown(() async {
      await documents.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final controller = DriveController(
      configured: true,
      store: local,
      gateway: fake,
      documents: documents,
      sharer: DocumentSharer(files: files),
      settings: settings,
      exporter: (_) async => const DrivePayload(subfolder: null, parts: []),
    );
    controller.account = const DriveAccount(email: 'user@gmail.com');
    await controller.considerAutoUpload('doc-9');
    expect(await local.get('doc-9'), isNull);

    await controller.setAutoUpload(true);
    await controller.considerAutoUpload('doc-9');
    expect((await local.get('doc-9'))!.status, DriveSyncStatus.failed);
    expect(settings.settings.driveAutoUpload, isTrue);
  });
}

class _FakeGateway implements DriveGateway {
  final existingIds = <List<String>>[];
  final subfolders = <String?>[];
  bool failNext = false;
  List<double> progressSteps = const [0.5];
  var _sequence = 0;

  @override
  Future<DriveAccount?> restore() async => null;

  @override
  Future<DriveAccount> signIn() async {
    return const DriveAccount(email: 'user@gmail.com');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<List<String>> upload({
    required List<DrivePart> parts,
    required List<String> existingFileIds,
    required String? subfolder,
    required Future<void> Function(double progress) onProgress,
  }) async {
    existingIds.add(List<String>.from(existingFileIds));
    subfolders.add(subfolder);
    for (final step in progressSteps) {
      await onProgress(step);
    }
    if (failNext) {
      failNext = false;
      throw StateError('network');
    }
    if (existingFileIds.isNotEmpty) return List<String>.from(existingFileIds);
    _sequence++;
    return ['file-$_sequence'];
  }
}

