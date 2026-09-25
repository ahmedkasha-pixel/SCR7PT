import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/records.dart';
import '../../data/repositories/document_repository.dart';
import '../../features/share/document_sharer.dart';
import '../../app/settings_controller.dart';
import 'drive_gateway.dart';
import 'drive_models.dart';
import 'drive_queue.dart';
import 'drive_store.dart';

class DriveController extends ChangeNotifier {
  DriveController({
    required this.configured,
    required DriveLinkStore store,
    required DriveGateway gateway,
    required DocumentRepository documents,
    required DocumentSharer sharer,
    required SettingsController settings,
    this.previewAccount,
    DriveExporter? exporter,
    NetworkSnapshot? network,
  }) : _settings = settings,
       _queue = DriveQueue(
         store: store,
         gateway: gateway,
         wifiOnly: settings.settings.driveWifiOnly,
         network: network ?? NetworkSnapshot.onWifi,
         export:
             exporter ??
             (link) => _export(
               documents: documents,
               sharer: sharer,
               link: link,
             ),
       ) {
    _queue.onChanged = _reload;
    autoUpload = settings.settings.driveAutoUpload;
  }

  final bool configured;
  final DriveAccount? previewAccount;
  final SettingsController _settings;
  final DriveQueue _queue;

  DriveAccount? account;
  bool signingIn = false;
  Map<String, DriveLink> links = {};
  bool autoUpload = false;

  bool get wifiOnly => _queue.wifiOnly;

  DriveLink? linkFor(String documentId) => links[documentId];

  Future<void> start({NetworkMonitor? monitor}) async {
    if (previewAccount != null) {
      account = previewAccount;
    } else if (configured) {
      try {
        account = await _queue.gateway.restore();
      } catch (error) {
        debugPrint('Drive restore failed: $error');
      }
    }
    await _reload();
    if (monitor != null) {
      final current = await monitor.current();
      _queue.network = current;
      monitor.changes.listen((snapshot) {
        _queue.network = snapshot;
        unawaited(_queue.pump());
      });
    }
    notifyListeners();
    await _queue.pump();
  }

  Future<DriveSaveResult> saveDocument(
    String documentId, {
    ShareFormat? format,
    CompressionLevel? compression,
  }) async {
    if (!configured) return DriveSaveResult.notConfigured;
    if (account == null) return DriveSaveResult.needsSignIn;
    await _queue.enqueue(
      documentId: documentId,
      format: format ?? _settings.settings.shareFormat,
      compression: compression ?? _settings.settings.compression,
    );
    return DriveSaveResult.queued;
  }

  Future<void> considerAutoUpload(String documentId) async {
    if (!configured || !autoUpload || account == null) return;
    await saveDocument(documentId);
  }

  Future<void> retry(String documentId) => _queue.retry(documentId);

  /// Puts a link straight into the store. Screenshot tests use this to show
  /// uploading and failed badges without calling the network.
  @visibleForTesting
  Future<void> seedLink(DriveLink link) async {
    await _queue.store.put(link);
    await _reload();
  }

  Future<void> signIn() async {
    if (!configured) return;
    signingIn = true;
    notifyListeners();
    try {
      account = await _queue.gateway.signIn();
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _queue.gateway.signOut();
    account = null;
    notifyListeners();
  }

  Future<void> setAutoUpload(bool value) async {
    autoUpload = value;
    await _settings.setDriveAutoUpload(value);
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    _queue.wifiOnly = value;
    await _settings.setDriveWifiOnly(value);
    notifyListeners();
    await _queue.pump();
  }

  Future<void> _reload() async {
    final items = await _queue.store.all();
    links = {for (final link in items) link.documentId: link};
    notifyListeners();
  }
}

abstract class NetworkMonitor {
  Future<NetworkSnapshot> current();

  Stream<NetworkSnapshot> get changes;
}

class PluginNetworkMonitor implements NetworkMonitor {
  PluginNetworkMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<NetworkSnapshot> current() async {
    return _snapshot(await _connectivity.checkConnectivity());
  }

  @override
  Stream<NetworkSnapshot> get changes {
    return _connectivity.onConnectivityChanged.map(_snapshot);
  }

  NetworkSnapshot _snapshot(List<ConnectivityResult> results) {
    final online = results.any((item) => item != ConnectivityResult.none);
    final wifi = results.any(
      (item) =>
          item == ConnectivityResult.wifi ||
          item == ConnectivityResult.ethernet,
    );
    return NetworkSnapshot(online: online, wifi: wifi);
  }
}

Future<DrivePayload> _export({
  required DocumentRepository documents,
  required DocumentSharer sharer,
  required DriveLink link,
}) async {
  final document = await documents.documentById(link.documentId);
  if (document == null) {
    throw StateError('Document is gone.');
  }
  final pages = await documents.pagesFor(link.documentId);
  final files = await sharer.prepareFiles(
    document: document,
    pages: pages,
    format: link.format,
    compression: link.compression,
  );
  String? subfolder;
  final folderId = document.folderId;
  if (folderId != null) {
    final folders = await documents.listFolders();
    for (final folder in folders) {
      if (folder.id == folderId) {
        subfolder = folder.name;
        break;
      }
    }
  }
  return DrivePayload(
    subfolder: subfolder,
    parts: [
      for (final file in files)
        DrivePart(name: file.name, mimeType: file.mimeType, bytes: file.bytes),
    ],
  );
}
