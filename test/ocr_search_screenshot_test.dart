import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

void main() {
  testWidgets('Arabic search screenshots for a word and a phone fragment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    final harness = (await tester.runAsync(() async {
      final created = await createHarness(
        preferences: const {'language_code': 'ar'},
      );
      await _seed(created);
      await created.library.refresh();
      return created;
    }))!;
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      RepaintBoundary(key: const Key('shot'), child: harness.app),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('camera-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byKey(const Key('search-field')), 'راميه');
    await tester.pump();
    expect(find.text('تقرير المختبر'), findsOneWidget);
    expect(find.text('داخل الصفحات'), findsOneWidget);
    expect(find.textContaining('رامية'), findsWidgets);
    expect(find.text('صفحة 2'), findsOneWidget);
    expect(find.textContaining('راميه'), findsWidgets);
    await _capture(tester, 'search-ramiya-ar');

    await tester.enterText(find.byKey(const Key('search-field')), '4567');
    await tester.pump();
    expect(find.text('ملاحظات العيادة'), findsOneWidget);
    expect(find.text('تقرير المختبر'), findsNothing);
    expect(find.textContaining('4567'), findsWidgets);
    expect(find.text('صفحة 1'), findsOneWidget);
    await _capture(tester, 'search-digits-ar');

    final copied = (await tester.runAsync(() async {
      final first = await File(
        'build/screenshots/ocr-search/search-ramiya-ar.png',
      ).readAsBytes();
      final second = await File(
        'build/screenshots/ocr-search/search-digits-ar.png',
      ).readAsBytes();
      final destination = Directory(
        '/opt/cursor/artifacts/scr7pt/ocr-search/screens',
      );
      await destination.create(recursive: true);
      await File('${destination.path}/search-ramiya-ar.png').writeAsBytes(first);
      await File('${destination.path}/search-digits-ar.png').writeAsBytes(second);
      return first.length != second.length;
    }))!;
    expect(copied, isTrue);
  });
}

Future<void> _seed(TestHarness harness) async {
  final image = img.Image(width: 240, height: 320, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(248, 246, 240));
  img.fillRect(
    image,
    x1: 24,
    y1: 36,
    x2: 210,
    y2: 52,
    color: img.ColorRgb8(40, 48, 58),
  );
  final jpeg = img.encodeJpg(image, quality: 90);
  NewPage page(String id) {
    return NewPage(
      id: id,
      originalJpeg: jpeg,
      processedJpeg: jpeg,
      filter: PageFilter.original,
      corners: Quad.standard,
    );
  }

  final lab = await harness.documents.createDocument(
    name: 'تقرير المختبر',
    pages: [page('lab-1'), page('lab-2')],
  );
  final labPages = await harness.documents.pagesFor(lab.id);
  await harness.documents.savePageText(
    pageId: labPages[0].id,
    documentId: lab.id,
    position: 0,
    rawText: 'غلاف التقرير الطبي',
  );
  await harness.documents.savePageText(
    pageId: labPages[1].id,
    documentId: lab.id,
    position: 1,
    rawText: 'اسم المريضة رامية بنت أحمد',
  );

  final clinic = await harness.documents.createDocument(
    name: 'ملاحظات العيادة',
    pages: [page('clinic-1')],
  );
  final clinicPages = await harness.documents.pagesFor(clinic.id);
  await harness.documents.savePageText(
    pageId: clinicPages.single.id,
    documentId: clinic.id,
    position: 0,
    rawText: 'هاتف العيادة (055) 123-4567',
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  final file = File('build/screenshots/ocr-search/$name.png');
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List());
  });
  image.dispose();
}

Future<void> _loadFonts() async {
  final arabic = FontLoader(AppTheme.arabicFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    arabic.addFont(_bytes('assets/fonts/IBMPlexSansArabic-$weight.ttf'));
  }
  await arabic.load();
  final inter = FontLoader(AppTheme.latinFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(_bytes('assets/fonts/Inter-$weight.ttf'));
  }
  await inter.load();
  final icons = FontLoader('MaterialIcons');
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/develop/flutter';
  icons.addFont(
    _bytes(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  );
  await icons.load();
}

Future<ByteData> _bytes(String path) async {
  final data = await File(path).readAsBytes();
  return ByteData.sublistView(data);
}
