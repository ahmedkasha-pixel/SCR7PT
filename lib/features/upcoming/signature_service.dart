import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Phase 2 slot for signatures.
///
/// The primary path is importing a signature photo from the camera or gallery,
/// removing the white/paper background so the mark is transparent, saving it
/// for reuse, and placing it on a page with move and resize. Drawing with a
/// finger is a secondary option and should land behind import.
abstract class SignatureService {
  Future<Uint8List> importAndRemoveBackground(Uint8List imageBytes);

  Future<void> saveSignature({required String name, required Uint8List png});

  Future<void> placeOnPage({
    required String pageId,
    required String signatureId,
    required Rect normalizedFrame,
  });
}
