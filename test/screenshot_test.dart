import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/features/document/document_screen.dart';
import 'package:docscan/features/scan/page_editor.dart';
import 'package:docscan/features/scan/scan_session.dart';
import 'package:docscan/widgets/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

void main() {
  testWidgets('writes Dark Tech screenshots', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    final page = _samplePage();
    final preview = Uint8List.fromList(page.processedJpeg);
    final harness = (await tester.runAsync(
      () => createHarness(
        preferences: const {'language_code': 'ar'},
        preview: preview,
        picture: preview,
      ),
    ))!;
    addTearDown(harness.dispose);

    late DocumentRecord contract;
    late List<PageRecord> pages;
    await tester.runAsync(() async {
      final work = await harness.documents.createFolder('عمل');
      await harness.documents.createFolder('فواتير');
      contract = await harness.documents.createDocument(
        name: 'عقد الإيجار',
        folderId: work.id,
        pages: [page],
      );
      pages = await harness.documents.pagesFor(contract.id);
      await harness.library.refresh();
    });

    await tester.pumpWidget(
      RepaintBoundary(key: const Key('shot'), child: harness.app),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shutter-button')), findsOneWidget);
    await _save(tester, 'camera-ar');

    await tester.tap(find.byKey(const Key('camera-close')));
    await tester.pumpAndSettle();
    expect(find.text('عقد الإيجار'), findsOneWidget);
    await _save(tester, 'home-dark-ar');

    _push(
      tester,
      PageEditor(
        session: _session(preview, cropping: true),
        onAddPage: () {},
        onDone: () async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('معاينة'), findsOneWidget);
    await _save(tester, 'crop-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(
      tester,
      PageEditor(
        session: _session(preview, cropping: false),
        onAddPage: () {},
        onDone: () async {},
        showAdd: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تحسين تلقائي'), findsOneWidget);
    expect(find.text('الأصل'), findsOneWidget);
    await _save(tester, 'filters-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(tester, DocumentScreen(document: contract, initialPages: pages));
    await tester.pumpAndSettle();
    expect(find.text('عقد الإيجار'), findsOneWidget);
    await _save(tester, 'document-ar');

    final sheetContext = tester.element(find.byType(DocumentScreen));
    showModalBottomSheet<void>(
      context: sheetContext,
      builder: (_) => const ShareFormatSheet(initial: ShareFormat.pdf),
    );
    await tester.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);
    await _save(tester, 'share-ar');
    _pop(tester);
    await tester.pumpAndSettle();
    _pop(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('داكن'), findsOneWidget);
    await _save(tester, 'settings-ar');

    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();
    _pop(tester);
    await tester.pumpAndSettle();
    expect(find.text('عقد الإيجار'), findsOneWidget);
    await _save(tester, 'home-light-ar');
  });
}

void _push(WidgetTester tester, Widget page) {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(MaterialPageRoute<void>(builder: (_) => page));
}

void _pop(WidgetTester tester) {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
}

void _expectArabicFonts(WidgetTester tester) {
  final arabic = RegExp(r'[\u0600-\u06FF]');
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    final text = render.text.toPlainText();
    if (!arabic.hasMatch(text)) continue;
    final style = render.text.style;
    expect(
      style?.fontFamilyFallback,
      contains(AppTheme.arabicFamily),
      reason: text,
    );
    final weight = style?.fontWeight;
    if (weight != null) {
      expect(weight.value, lessThanOrEqualTo(700), reason: text);
    }
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  _expectArabicFonts(tester);
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  final file = File('build/screenshots/$name.png');
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

NewPage _samplePage() {
  final image = _pageImage();
  final jpeg = img.encodeJpg(image, quality: 85);
  return NewPage(
    id: 'page-1',
    originalJpeg: jpeg,
    processedJpeg: jpeg,
    filter: PageFilter.original,
    corners: Quad.standard,
  );
}

ScanSession _session(Uint8List jpeg, {required bool cropping}) {
  final session = ScanSession();
  session.pages.add(
    EditablePage(
      id: 'shot-page',
      originalJpeg: jpeg,
      previewJpeg: jpeg,
      corners: Quad.standard,
      width: 480,
      height: 680,
      cropping: cropping,
    ),
  );
  return session;
}

img.Image _pageImage() {
  final image = img.Image(width: 480, height: 680, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(55, 48, 42));
  img.fillRect(
    image,
    x1: 46,
    y1: 36,
    x2: 434,
    y2: 640,
    color: img.ColorRgb8(244, 242, 236),
  );
  img.fillRect(
    image,
    x1: 78,
    y1: 72,
    x2: 280,
    y2: 96,
    color: img.ColorRgb8(37, 99, 235),
  );
  for (var line = 0; line < 10; line++) {
    img.fillRect(
      image,
      x1: 78,
      y1: 124 + line * 34,
      x2: line.isEven ? 390 : 320,
      y2: 138 + line * 34,
      color: img.ColorRgb8(170, 166, 158),
    );
  }
  return image;
}
