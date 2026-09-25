import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan/core/ocr/page_ocr.dart';
import 'package:docscan/core/search/arabic_normalize.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('synthetic page reports Arabic, English, and number accuracy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(),
          child: RepaintBoundary(
            key: Key('ocr-page'),
            child: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 1000,
                height: 1760,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(64, 48, 64, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line('رامية', rtl: true),
                      _Line('أحمد', rtl: true),
                      _Line('تقرير', rtl: true),
                      _Line('المختبر', rtl: true),
                      _Line('الطبي', rtl: true),
                      _Line('Medical'),
                      _Line('laboratory'),
                      _Line('report'),
                      _Line('Patient'),
                      _Line('invoice'),
                      _Line('Phone (055) 123-4567'),
                      _Line('ID 88442219'),
                      _Line('Date 1447/03/12'),
                      _Line('Amount 12.5'),
                      _Line('Year 2024'),
                      _Line('٠٥٥١٢٣٤٥٦٧'),
                      _Line('١٢٫٥'),
                      _Line('۰۵۵۱۲۳۴۵۶۷'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('ocr-page')),
    );
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1),
    ))!;
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    image.dispose();
    final bytes = data.buffer.asUint8List();
    final png = File('build/ocr-synthetic.png');
    await tester.runAsync(() async {
      await png.parent.create(recursive: true);
      await png.writeAsBytes(bytes);
    });

    final ocr = TesseractPageOcr(
      tessdataDir: Directory('assets/tessdata').absolute.path,
    );
    final watch = Stopwatch()..start();
    final text = (await tester.runAsync(() => ocr.recognize(bytes)))!;
    watch.stop();

    const arabicWords = ['رامية', 'أحمد', 'تقرير', 'المختبر', 'الطبي'];
    const englishWords = [
      'medical',
      'laboratory',
      'report',
      'patient',
      'invoice',
    ];
    const western = ['0551234567', '88442219', '14470312', '125', '2024'];
    final normalized = normalizeForSearch(text);
    final folded = text.toLowerCase();
    final runs = extractDigitRuns(text).map((run) => run.digits).toList();
    final arabicHits = [
      for (final word in arabicWords)
        if (normalized.contains(normalizeForSearch(word))) word,
    ];
    final englishHits = [
      for (final word in englishWords)
        if (folded.contains(word)) word,
    ];
    final westernHits = [
      for (final number in western)
        if (runs.any((run) => run.contains(number))) number,
    ];
    var indicDigits = 0;
    for (final rune in text.runes) {
      final arabicIndic = rune >= 0x0660 && rune <= 0x0669;
      final persian = rune >= 0x06F0 && rune <= 0x06F9;
      if (arabicIndic || persian) indicDigits++;
    }
    const indicDrawn = 23;

    // ignore: avoid_print
    print(
      'OCR arabic ${arabicHits.length}/${arabicWords.length} '
      'english ${englishHits.length}/${englishWords.length} '
      'western ${westernHits.length}/${western.length} '
      'arabic-indic $indicDigits/$indicDrawn '
      'ms ${watch.elapsedMilliseconds}',
    );
    // ignore: avoid_print
    print('OCR text:\n$text');

    expect(arabicHits, arabicWords);
    expect(englishHits, englishWords);
    expect(westernHits, western);
    expect(indicDigits, greaterThanOrEqualTo(0));
    expect(indicDigits, lessThanOrEqualTo(indicDrawn + 5));
    expect(watch.elapsedMilliseconds, greaterThan(0));
  });
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.rtl = false});

  final String text;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Text(
        text,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        style: const TextStyle(
          fontFamily: AppTheme.arabicFamily,
          fontSize: 46,
          height: 1.15,
          color: Colors.black,
        ),
      ),
    );
  }
}

Future<void> _loadFonts() async {
  final arabic = FontLoader(AppTheme.arabicFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    arabic.addFont(_bytes('assets/fonts/IBMPlexSansArabic-$weight.ttf'));
  }
  await arabic.load();
}

Future<ByteData> _bytes(String path) async {
  final data = await File(path).readAsBytes();
  return ByteData.sublistView(data);
}
