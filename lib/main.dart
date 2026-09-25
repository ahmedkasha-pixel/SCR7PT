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
import 'data/storage/file_store.dart';
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
  runApp(
    DocScanApp(
      library: LibraryController(documents),
      settings: settings,
      documents: documents,
      signatures: signatures,
      sharer: DocumentSharer(files: files, signatures: signatures),
      gallery: ImagePickerGallery(),
      createCamera: LiveScanCamera.new,
    ),
  );
}
