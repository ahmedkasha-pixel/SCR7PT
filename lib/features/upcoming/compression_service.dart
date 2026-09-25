import 'dart:typed_data';

/// Phase 2. Quality levels for local file compression.
enum CompressionLevel { high, medium, low }

/// Phase 2 slot. The UI lists this work as upcoming and does not call it yet.
///
/// A later implementation should recompress page JPEGs at [CompressionLevel]
/// and report the resulting byte size before the user commits.
abstract class CompressionService {
  Future<Uint8List> compress(Uint8List jpeg, CompressionLevel level);

  int resultingSize(Uint8List jpeg, CompressionLevel level);
}
