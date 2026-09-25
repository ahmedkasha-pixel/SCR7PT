import 'dart:typed_data';

import '../../data/models/records.dart';

/// Phase 2 slot. Sharing uses [CompressionLevel] directly.
///
/// A later implementation should recompress page JPEGs at [CompressionLevel]
/// and report the resulting byte size before the user commits.
abstract class CompressionService {
  Future<Uint8List> compress(Uint8List jpeg, CompressionLevel level);

  int resultingSize(Uint8List jpeg, CompressionLevel level);
}
