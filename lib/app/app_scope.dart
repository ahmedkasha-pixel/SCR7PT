import 'package:flutter/widgets.dart';

import '../data/repositories/document_repository.dart';
import '../data/repositories/signature_repository.dart';
import '../features/scan/gallery_picker.dart';
import '../features/scan/scan_camera.dart';
import '../features/share/document_sharer.dart';
import '../features/upcoming/upcoming_services.dart';
import 'library_controller.dart';
import 'settings_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    required this.library,
    required this.settings,
    required this.documents,
    required this.signatures,
    required this.gallery,
    required this.createCamera,
    required this.sharer,
    required this.upcoming,
    required super.child,
    super.key,
  });

  final LibraryController library;
  final SettingsController settings;
  final DocumentRepository documents;
  final SignatureRepository signatures;
  final GalleryPicker gallery;
  final ScanCamera Function() createCamera;
  final DocumentSharer sharer;
  final UpcomingServices upcoming;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
