import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/models/records.dart';
import 'pdf_exporter.dart';
import 'signature_stamp.dart';

/// Long side and JPEG quality for each share level.
({int maxLong, int quality}) compressionSpec(CompressionLevel level) {
  switch (level) {
    case CompressionLevel.high:
      return (maxLong: 100000, quality: 90);
    case CompressionLevel.medium:
      return (maxLong: 2000, quality: 75);
    case CompressionLevel.low:
      return (maxLong: 1400, quality: 60);
  }
}

/// File sizes for the share sheet. The numbers are the encoded bytes.
class ExportSizes {
  const ExportSizes({
    required this.original,
    required this.jpg,
    required this.pdf,
  });

  final int original;
  final Map<CompressionLevel, int> jpg;
  final Map<CompressionLevel, int> pdf;

  int bytesFor(ShareFormat format, CompressionLevel level) {
    final table = format == ShareFormat.pdf ? pdf : jpg;
    return table[level] ?? original;
  }
}

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Uint8List compressJpeg(Uint8List jpeg, CompressionLevel level) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) return jpeg;
  return Uint8List.fromList(
    img.encodeJpg(_scaled(decoded, level), quality: compressionSpec(level).quality),
  );
}

img.Image _scaled(img.Image source, CompressionLevel level) {
  final maxLong = compressionSpec(level).maxLong;
  final long = math.max(source.width, source.height);
  if (long <= maxLong) return source;
  final scale = maxLong / long;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}

class MeasureRequest {
  MeasureRequest({required this.pages, required this.stamps});

  final List<Uint8List> pages;
  final List<List<StampPayload>> stamps;
}

class RenderExportRequest {
  RenderExportRequest({
    required this.pages,
    required this.stamps,
    required this.levelName,
  });

  final List<Uint8List> pages;
  final List<List<StampPayload>> stamps;
  final String levelName;
}

Future<ExportSizes> measureExport(MeasureRequest request) async {
  final original = request.pages.fold<int>(0, (sum, page) => sum + page.length);
  final jpg = <CompressionLevel, int>{};
  final pdf = <CompressionLevel, int>{};
  for (final level in CompressionLevel.values) {
    final images = _render(request.pages, request.stamps, level);
    jpg[level] = images.fold<int>(0, (sum, page) => sum + page.length);
    pdf[level] = (await PdfExporter().build(images)).length;
  }
  return ExportSizes(original: original, jpg: jpg, pdf: pdf);
}

List<Uint8List> renderExport(RenderExportRequest request) {
  final level = CompressionLevel.values.byName(request.levelName);
  return _render(request.pages, request.stamps, level);
}

List<Uint8List> _render(
  List<Uint8List> pages,
  List<List<StampPayload>> stamps,
  CompressionLevel level,
) {
  final quality = compressionSpec(level).quality;
  final output = <Uint8List>[];
  for (var i = 0; i < pages.length; i++) {
    final decoded = img.decodeImage(pages[i]);
    if (decoded == null) {
      output.add(pages[i]);
      continue;
    }
    final rgb = decoded.convert(format: img.Format.uint8, numChannels: 3);
    final marks = i < stamps.length ? stamps[i] : const <StampPayload>[];
    final stamped = marks.isEmpty ? rgb : stampImage(rgb, marks);
    final scaled = _scaled(stamped, level);
    output.add(Uint8List.fromList(img.encodeJpg(scaled, quality: quality)));
  }
  return output;
}
