import 'dart:io';
import 'dart:typed_data';

import 'package:docscan/app.dart';
import 'package:docscan/app/library_controller.dart';
import 'package:docscan/app/settings_controller.dart';
import 'package:docscan/data/db/app_database.dart';
import 'package:docscan/data/repositories/document_repository.dart';
import 'package:docscan/data/repositories/settings_repository.dart';
import 'package:docscan/data/repositories/signature_repository.dart';
import 'package:docscan/data/storage/file_store.dart';
import 'package:docscan/features/scan/gallery_picker.dart';
import 'package:docscan/features/scan/scan_camera.dart';
import 'package:docscan/features/drive/drive_controller.dart';
import 'package:docscan/features/drive/drive_gateway.dart';
import 'package:docscan/features/drive/drive_models.dart';
import 'package:docscan/features/drive/drive_store.dart';
import 'package:docscan/features/share/document_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sqlite_setup.dart';

class FakeGallery implements GalleryPicker {
  FakeGallery(this.images);

  final List<Uint8List> images;

  @override
  Future<List<Uint8List>> pickImages() async => images;
}

class FakeScanCamera implements ScanCamera {
  FakeScanCamera(this.picture, {this.preview});

  final Uint8List picture;
  final Uint8List? preview;
  bool flash = false;

  @override
  Future<ScanCameraStatus> initialize() async => ScanCameraStatus.ready;

  @override
  Widget buildPreview() {
    final bytes = preview;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return const ColoredBox(
      color: Color(0xFF0F172A),
      child: Center(
        child: Icon(
          Icons.document_scanner_outlined,
          color: Colors.white,
          size: 72,
        ),
      ),
    );
  }

  @override
  Future<Uint8List> takePicture() async => picture;

  @override
  Future<void> setFlash(bool enabled) async {
    flash = enabled;
  }

  @override
  Future<void> dispose() async {}
}

class TestHarness {
  TestHarness({
    required this.app,
    required this.documents,
    required this.signatures,
    required this.library,
    required this.directory,
    required this.shared,
    required this.files,
  });

  final DocScanApp app;
  final DocumentRepository documents;
  final SignatureRepository signatures;
  final LibraryController library;
  final Directory directory;
  final List<ShareParams> shared;
  final FileStore files;

  Future<void> dispose() async {
    await documents.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class FakeDriveGateway implements DriveGateway {
  @override
  Future<DriveAccount?> restore() async => null;

  @override
  Future<DriveAccount> signIn() async {
    return const DriveAccount(email: 'user@gmail.com', displayName: 'مستخدم');
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
    await onProgress(1);
    return existingFileIds.isEmpty
        ? ['drive-file']
        : List<String>.from(existingFileIds);
  }
}

Future<TestHarness> createHarness({
  Map<String, Object> preferences = const {},
  List<Uint8List> gallery = const [],
  Uint8List? picture,
  Uint8List? preview,
  bool driveConfigured = false,
  DriveAccount? driveAccount,
  List<DriveLink> driveLinks = const [],
  DriveGateway? driveGateway,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite();
  SharedPreferences.setMockInitialValues(preferences);
  final directory = await Directory.systemTemp.createTemp('docscan_ui_');
  final files = FileStore(Directory('${directory.path}/files'));
  final database = AppDatabase(path: '${directory.path}/db.sqlite');
  final documents = DocumentRepository(database: database, files: files);
  final signatures = SignatureRepository(database: database, files: files);
  final settings = SettingsController(SettingsRepository());
  await settings.load();
  final library = LibraryController(documents);
  final shared = <ShareParams>[];
  final sharer = DocumentSharer(
    signatures: signatures,
    files: files,
    share: (params) async {
      shared.add(params);
    },
  );
  final driveStore = MemoryDriveStore();
  for (final link in driveLinks) {
    await driveStore.put(link);
  }
  final drive = DriveController(
    configured: driveConfigured,
    previewAccount: driveAccount,
    store: driveStore,
    gateway: driveGateway ?? FakeDriveGateway(),
    documents: documents,
    sharer: sharer,
    settings: settings,
  );
  documents.onDocumentChanged = drive.considerAutoUpload;
  await drive.start();
  final app = DocScanApp(
    library: library,
    settings: settings,
    documents: documents,
    signatures: signatures,
    sharer: sharer,
    drive: drive,
    gallery: FakeGallery(gallery),
    createCamera: () =>
        FakeScanCamera(picture ?? Uint8List(0), preview: preview),
  );
  return TestHarness(
    app: app,
    documents: documents,
    signatures: signatures,
    library: library,
    directory: directory,
    shared: shared,
    files: files,
  );
}
