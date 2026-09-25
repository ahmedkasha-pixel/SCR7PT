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
  testWidgets('Arabic, English, fuzzy search & indexing indicator screenshots', (
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

    // 1. Search Arabic (with typo tolerance: searching 'المستاجر' matching 'المستاج')
    await tester.enterText(find.byKey(const Key('search-field')), 'المستاجر');
    await tester.pump();
    expect(find.text('عقد إيجار'), findsOneWidget);
    expect(find.text('داخل الصفحات'), findsOneWidget);
    await _capture(tester, 'search-arabic-query');

    // 2. Search English (searching 'invoice' matching English invoice in pages)
    await tester.enterText(find.byKey(const Key('search-field')), 'invoice');
    await tester.pump();
    expect(find.text('فاتورة استشارية'), findsOneWidget);
    expect(find.text('داخل الصفحات'), findsOneWidget);
    await _capture(tester, 'search-english-query');

    // 3. Clear search and show indexing progress indicator: 12/40
    await tester.enterText(find.byKey(const Key('search-field')), '');
    harness.library.setIndexing(12, 40);
    await tester.pump();
    expect(find.byKey(const Key('search-indexing')), findsOneWidget);
    expect(find.text('جاري تجهيز البحث داخل المستندات 12/40'), findsOneWidget);
    await _capture(tester, 'search-indexing-progress');

    // Reset indexing for clean state
    harness.library.setIndexing(0, 0);
    await tester.pump();

    // Composite Arabic and English queries into a single comparison board
    final copied = (await tester.runAsync(() async {
      final arBytes = await File('build/screenshots/ocr-search/search-arabic-query.png').readAsBytes();
      final enBytes = await File('build/screenshots/ocr-search/search-english-query.png').readAsBytes();
      final idxBytes = await File('build/screenshots/ocr-search/search-indexing-progress.png').readAsBytes();

      final arImg = img.decodePng(arBytes)!;
      final enImg = img.decodePng(enBytes)!;
      
      // Side by side composite: width = arImg.width + enImg.width + 40
      final gap = 40;
      final compW = arImg.width + enImg.width + gap;
      final compH = arImg.height;
      final comp = img.Image(width: compW, height: compH);
      img.fill(comp, color: img.ColorRgb8(15, 23, 42)); // App background navy
      img.compositeImage(comp, arImg, dstX: 0, dstY: 0);
      img.compositeImage(comp, enImg, dstX: arImg.width + gap, dstY: 0);

      final compBytes = Uint8List.fromList(img.encodePng(comp));

      final destination = Directory('/opt/cursor/artifacts/scr7pt/ocr-search/screens');
      await destination.create(recursive: true);
      await File('${destination.path}/search-queries-comparison.png').writeAsBytes(compBytes);
      await File('${destination.path}/search-indexing-progress.png').writeAsBytes(idxBytes);

      return compBytes.isNotEmpty && idxBytes.isNotEmpty;
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

  // Document 1: Contract with OCR typo in Arabic (المستاج instead of المستاجر)
  final contract = await harness.documents.createDocument(
    name: 'عقد إيجار',
    pages: [page('contract-1')],
  );
  final contractPages = await harness.documents.pagesFor(contract.id);
  await harness.documents.savePageText(
    pageId: contractPages[0].id,
    documentId: contract.id,
    position: 0,
    rawText: 'بيانات المستاج والطرف الاول المؤجر سليمان في حي الملقا بالرياض',
  );

  // Document 2: English invoice with consulting deliverables
  final invoice = await harness.documents.createDocument(
    name: 'فاتورة استشارية',
    pages: [page('inv-1')],
  );
  final invPages = await harness.documents.pagesFor(invoice.id);
  await harness.documents.savePageText(
    pageId: invPages[0].id,
    documentId: invoice.id,
    position: 0,
    rawText: 'TAX INVOICE Apex Consulting Services Total invioce amount 13800',
  );

  // Document 3: Clinic report
  final clinic = await harness.documents.createDocument(
    name: 'ملاحظات العيادة',
    pages: [page('clinic-1')],
  );
  final clinicPages = await harness.documents.pagesFor(clinic.id);
  await harness.documents.savePageText(
    pageId: clinicPages.single.id,
    documentId: clinic.id,
    position: 0,
    rawText: 'هاتف العيادة (055) 123-4567 داخلي 4567',
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
