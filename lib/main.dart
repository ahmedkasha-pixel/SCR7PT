import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'app/library_controller.dart';
import 'app/settings_controller.dart';
import 'core/app_config.dart';
import 'data/db/app_database.dart';
import 'data/repositories/document_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/signature_repository.dart';
import 'core/google_config.dart';
import 'core/ocr/page_ocr.dart';
import 'data/storage/file_store.dart';
import 'features/search/page_indexer.dart';
import 'features/drive/drive_controller.dart';
import 'features/drive/drive_store.dart';
import 'features/drive/google_drive_gateway.dart';
import 'features/scan/gallery_picker.dart';
import 'features/scan/scan_camera.dart';
import 'features/share/document_sharer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  final root = Directory('${directory.path}/docscan');
  await root.create(recursive: true);
  final files = FileStore(root);
  final database = AppDatabase(
    path: '${root.path}/${AppConfig.databaseFileName}',
  );
  final documents = DocumentRepository(database: database, files: files);
  final signatures = SignatureRepository(database: database, files: files);
  final settings = SettingsController(SettingsRepository());
  await settings.load();
  final sharer = DocumentSharer(files: files, signatures: signatures);
  final drive = DriveController(
    configured: GoogleConfig.isConfigured,
    store: SqliteDriveStore(database),
    gateway: GoogleDriveGateway(),
    documents: documents,
    sharer: sharer,
    settings: settings,
  );
  documents.onDocumentChanged = drive.considerAutoUpload;
  final library = LibraryController(documents);
  final indexer = PageIndexer(
    documents: documents,
    ocr: TesseractPageOcr(),
    onIndexed: library.upsertIndexed,
    onIndexing: library.setIndexing,
  );
  documents.onPagesReady = (pages) => indexer.enqueue(pages, urgent: true);
  await drive.start(
    monitor: GoogleConfig.isConfigured ? PluginNetworkMonitor() : null,
  );
  runApp(
    DocScanApp(
      library: library,
      settings: settings,
      documents: documents,
      signatures: signatures,
      sharer: sharer,
      drive: drive,
      gallery: ImagePickerGallery(),
      createCamera: LiveScanCamera.new,
    ),
  );
  // Index existing pages only after the first frame, and never let a failure
  // there surface as a launch crash. Re-indexes with the improved pipeline once
  // after upgrade.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final repo = SettingsRepository();
      final version = await repo.getOcrPipelineVersion();
      if (version < SettingsRepository.currentOcrPipelineVersion) {
        await repo.setOcrPipelineVersion(SettingsRepository.currentOcrPipelineVersion);
        unawaited(indexer.backfill(force: true));
      } else {
        unawaited(indexer.backfill());
      }
    } catch (e) {
      debugPrint('Startup indexing error: $e');
      unawaited(indexer.backfill());
    }
  });
}
