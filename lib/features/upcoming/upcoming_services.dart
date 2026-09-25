import 'cloud_storage.dart';
import 'compression_service.dart';
import 'signature_service.dart';

enum UpcomingKind { compression, signature, googleDrive }

class UpcomingEntry {
  const UpcomingEntry({required this.phase, required this.kind});

  final int phase;
  final UpcomingKind kind;
}

/// Extension points passed through the app so phases 2 and 3 can be wired
/// in without reshaping navigation or storage.
class UpcomingServices {
  const UpcomingServices({
    this.compression,
    this.signatures,
    this.cloud = const [],
  });

  final CompressionService? compression;
  final SignatureService? signatures;
  final List<CloudStorage> cloud;

  static const catalog = <UpcomingEntry>[
    UpcomingEntry(phase: 2, kind: UpcomingKind.compression),
    UpcomingEntry(phase: 2, kind: UpcomingKind.signature),
    UpcomingEntry(phase: 3, kind: UpcomingKind.googleDrive),
  ];
}
