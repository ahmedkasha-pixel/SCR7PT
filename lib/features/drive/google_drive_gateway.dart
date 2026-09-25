import 'dart:async';
import 'dart:math' as math;

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../core/google_config.dart';
import 'drive_gateway.dart';
import 'drive_models.dart';

/// Google Drive via the signed-in account. Sees only files this app created.
class GoogleDriveGateway implements DriveGateway {
  GoogleSignInAccount? _account;
  drive.DriveApi? _api;
  bool _initialized = false;
  final Map<String, String> _folders = {};

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: GoogleConfig.resolvedIosClientId.isEmpty
          ? null
          : GoogleConfig.resolvedIosClientId,
      serverClientId: GoogleConfig.resolvedWebClientId,
    );
    _initialized = true;
  }

  @override
  Future<DriveAccount?> restore() async {
    await _ensureInit();
    final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    _account = account;
    return _describe(account);
  }

  @override
  Future<DriveAccount> signIn() async {
    await _ensureInit();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: const [GoogleConfig.driveScope],
    );
    await account.authorizationClient.authorizeScopes(const [
      GoogleConfig.driveScope,
    ]);
    _account = account;
    _api = null;
    return _describe(account);
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _api = null;
    _folders.clear();
    if (_initialized) {
      await GoogleSignIn.instance.signOut();
    }
  }

  @override
  Future<List<String>> upload({
    required List<DrivePart> parts,
    required List<String> existingFileIds,
    required String? subfolder,
    required Future<void> Function(double progress) onProgress,
  }) async {
    final api = await _client();
    final parent = await _folderId(
      api,
      name: subfolder ?? GoogleConfig.driveFolderName,
      parentId: subfolder == null
          ? 'root'
          : await _folderId(
              api,
              name: GoogleConfig.driveFolderName,
              parentId: 'root',
            ),
    );
    final ids = <String>[];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final media = drive.Media(
        _chunks(part.bytes, (fraction) {
          unawaited(onProgress((index + fraction) / parts.length));
        }),
        part.bytes.length,
        contentType: part.mimeType,
      );
      final existing = index < existingFileIds.length
          ? existingFileIds[index]
          : null;
      final metadata = drive.File()
        ..name = part.name
        ..mimeType = part.mimeType;
      final drive.File saved;
      if (existing == null) {
        metadata.parents = [parent];
        saved = await api.files.create(
          metadata,
          uploadMedia: media,
          $fields: 'id',
        );
      } else {
        saved = await api.files.update(
          metadata,
          existing,
          uploadMedia: media,
          $fields: 'id',
        );
      }
      final id = saved.id;
      if (id == null || id.isEmpty) {
        throw StateError('Drive did not return a file id.');
      }
      ids.add(id);
    }
    for (var index = parts.length; index < existingFileIds.length; index++) {
      await api.files.delete(existingFileIds[index]);
    }
    await onProgress(1);
    return ids;
  }

  Future<drive.DriveApi> _client() async {
    final cached = _api;
    final account = _account;
    if (cached != null && account != null) return cached;
    if (account == null) {
      throw StateError('Not signed in to Google.');
    }
    var authorization = await account.authorizationClient.authorizationForScopes(
      const [GoogleConfig.driveScope],
    );
    authorization ??= await account.authorizationClient.authorizeScopes(const [
      GoogleConfig.driveScope,
    ]);
    final client = authorization.authClient(
      scopes: const [GoogleConfig.driveScope],
    );
    final api = drive.DriveApi(client);
    _api = api;
    return api;
  }

  Future<String> _folderId(
    drive.DriveApi api, {
    required String name,
    required String parentId,
  }) async {
    final key = '$parentId/$name';
    final cached = _folders[key];
    if (cached != null) return cached;
    final safe = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final listed = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' and name = '$safe' and trashed = false and '$parentId' in parents",
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id,name)',
    );
    final found = listed.files;
    if (found != null && found.isNotEmpty && found.first.id != null) {
      final id = found.first.id!;
      _folders[key] = id;
      return id;
    }
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId],
      $fields: 'id',
    );
    final id = created.id;
    if (id == null || id.isEmpty) {
      throw StateError('Could not create the Drive folder.');
    }
    _folders[key] = id;
    return id;
  }

  DriveAccount _describe(GoogleSignInAccount account) {
    return DriveAccount(
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }

  Stream<List<int>> _chunks(
    List<int> bytes,
    void Function(double fraction) onProgress,
  ) async* {
    if (bytes.isEmpty) {
      onProgress(1);
      return;
    }
    const size = 256 * 1024;
    for (var offset = 0; offset < bytes.length; offset += size) {
      final end = math.min(offset + size, bytes.length);
      onProgress(end / bytes.length);
      yield bytes.sublist(offset, end);
    }
  }
}
