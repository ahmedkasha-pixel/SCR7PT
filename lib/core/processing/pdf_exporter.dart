import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a multi-page PDF locally from JPEG page images.
class PdfExporter {
  Future<Uint8List> build(List<Uint8List> jpegPages) async {
    if (jpegPages.isEmpty) {
      throw ArgumentError('A PDF needs at least one page.');
    }
    final document = pw.Document();
    for (final bytes in jpegPages) {
      final image = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (context) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return document.save();
  }
}
