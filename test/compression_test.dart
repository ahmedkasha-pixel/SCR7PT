import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan/core/processing/compress.dart';
import 'package:docscan/core/processing/pdf_exporter.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('compression sizes descend and the filter colors stay', () async {
    final noisy = img.Image(width: 1800, height: 900, numChannels: 3);
    final random = math.Random(7);
    for (var y = 0; y < noisy.height; y++) {
      for (var x = 0; x < noisy.width; x++) {
        noisy.setPixelRgb(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
    }
    img.fillRect(
      noisy,
      x1: 8,
      y1: 8,
      x2: 40,
      y2: 40,
      color: img.ColorRgb8(220, 30, 30),
    );
    final jpeg = Uint8List.fromList(img.encodeJpg(noisy, quality: 90));

    final gray = img.Image(width: 80, height: 60, numChannels: 3);
    img.fill(gray, color: img.ColorRgb8(140, 140, 140));
    gray.setPixelRgb(10, 10, 40, 40, 40);
    final grayJpeg = Uint8List.fromList(img.encodeJpg(gray, quality: 90));

    final high = compressJpeg(jpeg, CompressionLevel.high);
    final medium = compressJpeg(jpeg, CompressionLevel.medium);
    final low = compressJpeg(jpeg, CompressionLevel.low);
    expect(high.length, greaterThan(medium.length));
    expect(medium.length, greaterThan(low.length));

    final lowImage = img.decodeImage(low)!;
    expect(math.max(lowImage.width, lowImage.height), lessThanOrEqualTo(1400));
    final mediumImage = img.decodeImage(medium)!;
    expect(math.max(mediumImage.width, mediumImage.height), lessThanOrEqualTo(2000));
    final red = mediumImage.getPixel(10, 10);
    expect(red.r, greaterThan(red.b + 20));

    final grayOut = img.decodeImage(compressJpeg(grayJpeg, CompressionLevel.low))!;
    final pixel = grayOut.getPixel(4, 4);
    expect((pixel.r - pixel.g).abs(), lessThan(3));
    expect((pixel.g - pixel.b).abs(), lessThan(3));

    final measured = await measureExport(
      MeasureRequest(pages: [jpeg], stamps: const [[]]),
    );
    expect(measured.jpg[CompressionLevel.high]! > measured.jpg[CompressionLevel.medium]!, isTrue);
    expect(measured.jpg[CompressionLevel.medium]! > measured.jpg[CompressionLevel.low]!, isTrue);
    expect(
      (measured.jpg[CompressionLevel.medium]! - medium.length).abs() / medium.length,
      lessThan(0.1),
    );
    final pdf = await PdfExporter().build([high]);
    expect(
      (measured.pdf[CompressionLevel.high]! - pdf.length).abs() / pdf.length,
      lessThan(0.1),
    );
  });
}
