import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../geometry/page_aspect.dart';

/// Builds a multi-page PDF locally from JPEG page images.
///
/// Every page uses the first image's physical size: A4 or Letter when the
/// pixels match those sheets, otherwise a page with the same aspect.
class PdfExporter {
  Future<Uint8List> build(List<Uint8List> jpegPages) async {
    if (jpegPages.isEmpty) {
      throw ArgumentError('A PDF needs at least one page.');
    }
    final format = formatForJpeg(jpegPages.first);
    final document = pw.Document();
    for (final bytes in jpegPages) {
      final image = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.FittedBox(
            fit: pw.BoxFit.fill,
            child: pw.Image(image),
          ),
        ),
      );
    }
    return document.save();
  }
}

/// A4 and Letter in PDF points when the JPEG is the matching 300 dpi size.
PdfPageFormat formatForJpeg(Uint8List jpeg) {
  final decoder = img.findDecoderForData(jpeg);
  final info = decoder?.startDecode(jpeg);
  if (info == null || info.width <= 0 || info.height <= 0) {
    return PdfPageFormat.a4;
  }
  return formatForPixels(info.width, info.height);
}

PdfPageFormat formatForPixels(int width, int height) {
  bool near(int value, int target) =>
      (value - target).abs() <= math.max(8, (target * 0.02).round());
  final portrait = height >= width;
  final short = math.min(width, height);
  final long = math.max(width, height);
  if (near(short, a4ShortPx) && near(long, a4LongPx)) {
    final sheet = portrait ? PdfPageFormat.a4 : PdfPageFormat.a4.landscape;
    return PdfPageFormat(sheet.width, sheet.height, marginAll: 0);
  }
  if (near(short, letterShortPx) && near(long, letterLongPx)) {
    final sheet = portrait ? PdfPageFormat.letter : PdfPageFormat.letter.landscape;
    return PdfPageFormat(sheet.width, sheet.height, marginAll: 0);
  }
  const base = 595.0;
  if (portrait) {
    return PdfPageFormat(base, base * height / width, marginAll: 0);
  }
  return PdfPageFormat(base * width / height, base, marginAll: 0);
}
