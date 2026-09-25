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
            'psm': '6',
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
      '6',
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

/// Grayscale and a mild upscale so small type is easier to read.
/// Runs on the caller isolate; the indexer calls it through [compute].
Uint8List prepareOcrImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = decoded.convert(format: img.Format.uint8, numChannels: 1);
  final longest = image.width > image.height ? image.width : image.height;
  // Cap the working size so a large photo cannot OOM the process during
  // first-launch indexing. Small pages are still upscaled.
  const maxEdge = 2000;
  if (longest > maxEdge) {
    final scale = maxEdge / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  } else if (longest < 1400) {
    final scale = 1400 / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Image preparation off the UI isolate.
Future<Uint8List> prepareOcrImageAsync(Uint8List bytes) {
  return compute(prepareOcrImage, bytes);
}
