import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan/core/processing/pdf_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int red) {
  final image = img.Image(width: 12, height: 8, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(red, 80, 40));
  return img.encodeJpg(image);
}

void main() {
  test('builds a local PDF with one page per image', () async {
    final bytes = await PdfExporter().build([_jpeg(200), _jpeg(20)]);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
  });

  test('refuses to build a PDF with no pages', () {
    expect(PdfExporter().build([]), throwsArgumentError);
  });
}
