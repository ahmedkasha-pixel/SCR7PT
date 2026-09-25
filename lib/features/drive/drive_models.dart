import 'dart:typed_data';

import '../../data/models/records.dart';

enum DriveSyncStatus { queued, uploading, uploaded, failed }

enum DriveSaveResult { queued, notConfigured, needsSignIn }

class DriveAccount {
  const DriveAccount({
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String email;
  final String? displayName;
  final String? photoUrl;

  String get initial {
    final name = (displayName ?? email).trim();
    if (name.isEmpty) return '?';
    return String.fromCharCode(name.runes.first).toUpperCase();
  }
}

class DrivePart {
  const DrivePart({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

class DrivePayload {
  const DrivePayload({required this.subfolder, required this.parts});

  /// App folder name to mirror under SCR7PT. Null keeps the file in SCR7PT.
  final String? subfolder;
  final List<DrivePart> parts;
}

class NetworkSnapshot {
  const NetworkSnapshot({required this.online, required this.wifi});

  final bool online;
  final bool wifi;

  static const offline = NetworkSnapshot(online: false, wifi: false);
  static const onWifi = NetworkSnapshot(online: true, wifi: true);
  static const mobile = NetworkSnapshot(online: true, wifi: false);
}

class DriveLink {
  const DriveLink({
    required this.documentId,
    required this.status,
    this.fileIds = const [],
    this.progress = 0,
    this.error,
    this.format = ShareFormat.pdf,
    this.compression = CompressionLevel.medium,
    required this.updatedAt,
  });

  final String documentId;
  final DriveSyncStatus status;
  final List<String> fileIds;
  final double progress;
  final String? error;
  final ShareFormat format;
  final CompressionLevel compression;
  final DateTime updatedAt;

  DriveLink copy({
    DriveSyncStatus? status,
    List<String>? fileIds,
    double? progress,
    String? error,
    bool clearError = false,
    ShareFormat? format,
    CompressionLevel? compression,
    DateTime? updatedAt,
  }) {
    return DriveLink(
      documentId: documentId,
      status: status ?? this.status,
      fileIds: fileIds ?? this.fileIds,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
      format: format ?? this.format,
      compression: compression ?? this.compression,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
