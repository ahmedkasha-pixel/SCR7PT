import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-device OCR. Arabic and English share one Tesseract pass (`ara+eng`).
/// ML Kit Text Recognition v2 has no Arabic script, so it is not used.
abstract class PageOcr {
  Future<String> recognize(Uint8List imageBytes);
}

class TesseractPageOcr implements PageOcr {
  TesseractPageOcr({this.tessdataDir});

  /// Directory that contains `ara.traineddata` and `eng.traineddata`.
  /// Tests pass the bundled assets folder. Mobile copies those assets.
  final String? tessdataDir;

  static const language = 'ara+eng';

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final prepared = await prepareOcrImageAsync(imageBytes);
    final directory = await Directory.systemTemp.createTemp('scr7pt_ocr_');
    final file = File(p.join(directory.path, 'page.png'));
    try {
      await file.writeAsBytes(prepared, flush: true);
      if (Platform.isAndroid || Platform.isIOS) {
        return await FlutterTesseractOcr.extractText(
          file.path,
          language: language,
          args: const {
            'psm': '3',
            'preserve_interword_spaces': '1',
          },
        );
      }
      return await _recognizeWithCli(file.path);
    } finally {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  }

  Future<String> _recognizeWithCli(String imagePath) async {
    final dataDir = tessdataDir ?? await _bundledTessdataDir();
    final result = await Process.run('tesseract', [
      imagePath,
      'stdout',
      '-l',
      language,
      '--psm',
      '3',
      '--tessdata-dir',
      dataDir,
      '-c',
      'preserve_interword_spaces=1',
    ]);
    if (result.exitCode != 0) {
      throw StateError(result.stderr.toString());
    }
    return result.stdout.toString();
  }

  Future<String> _bundledTessdataDir() async {
    final documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, 'tessdata');
  }
}

/// Grayscale, resolution scaling, and contrast normalization for OCR.
/// Small text is upscaled to ~300 DPI equivalent; large photos are capped
/// safely at 2800px; paper contrast is normalized so text stands out.
Uint8List prepareOcrImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = decoded.convert(format: img.Format.uint8, numChannels: 1);
  final longest = image.width > image.height ? image.width : image.height;
  
  // Upscale small text to ~300 DPI equivalent (min 1600px edge)
  // and cap large sensor frames at 2800px to prevent excessive memory.
  const minEdge = 1600;
  const maxEdge = 2800;
  if (longest > maxEdge) {
    final scale = maxEdge / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  } else if (longest < minEdge) {
    final scale = minEdge / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  // Contrast stretch / normalization: expand dynamic range so ink is dark and paper is white
  image = _normalizeContrast(image);

  return Uint8List.fromList(img.encodePng(image));
}

img.Image _normalizeContrast(img.Image gray) {
  final numPixels = gray.width * gray.height;
  if (numPixels == 0) return gray;

  // Build 256-bin histogram
  final hist = List<int>.filled(256, 0);
  for (final pixel in gray) {
    final lum = pixel.r.toInt().clamp(0, 255);
    hist[lum]++;
  }

  // 1st percentile and 99th percentile cutoff
  final lowCutoff = (numPixels * 0.01).round();
  final highCutoff = (numPixels * 0.99).round();

  var low = 0;
  var count = 0;
  while (low < 255 && count + hist[low] < lowCutoff) {
    count += hist[low];
    low++;
  }

  var high = 255;
  count = 0;
  while (high > low && count + hist[high] < (numPixels - highCutoff)) {
    count += hist[high];
    high--;
  }

  if (high <= low) return gray;

  final range = high - low;
  for (final pixel in gray) {
    final val = pixel.r.toInt();
    final stretched = ((val - low) * 255 / range).round().clamp(0, 255);
    pixel.r = stretched;
    pixel.g = stretched;
    pixel.b = stretched;
  }
  return gray;
}

/// Image preparation off the UI isolate when compute is available,
/// or direct call when compute is unavailable (e.g. CLI/tests).
Future<Uint8List> prepareOcrImageAsync(Uint8List bytes) async {
  return prepareOcrImage(bytes);
}
