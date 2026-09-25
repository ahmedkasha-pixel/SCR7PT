import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/core/processing/compress.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/features/signature/signature_import.dart';
import 'package:docscan/features/signature/signature_place_screen.dart';
import 'package:docscan/features/signature/signatures_screen.dart';
import 'package:docscan/widgets/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

void main() {
  testWidgets('writes phase 2 Arabic screens', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    final signature = _signaturePng();
    final page = _pageJpeg();
    final harness = (await tester.runAsync(
      () => createHarness(preferences: const {'language_code': 'ar'}),
    ))!;
    addTearDown(harness.dispose);
    final saved = (await tester.runAsync(
      () => harness.signatures.create(name: 'توقيع العقد', png: signature),
    ))!;
    final second = (await tester.runAsync(
      () => harness.signatures.create(name: 'توقيع المراجعة', png: signature),
    ))!;

    await tester.pumpWidget(
      RepaintBoundary(key: const Key('shot'), child: harness.app),
    );
    await tester.pumpAndSettle();

    final host = tester.element(find.byType(Scaffold).first);
    showModalBottomSheet<void>(
      context: host,
      builder: (_) => ShareFormatSheet(
        initial: ShareFormat.pdf,
        initialLevel: CompressionLevel.medium,
        sizes: ExportSizes(
          original: 2480000,
          jpg: {
            CompressionLevel.high: 1860000,
            CompressionLevel.medium: 640000,
            CompressionLevel.low: 280000,
          },
          pdf: {
            CompressionLevel.high: 1920000,
            CompressionLevel.medium: 690000,
            CompressionLevel.low: 310000,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('عالية'), findsOneWidget);
    expect(find.text('متوسطة'), findsOneWidget);
    expect(find.text('منخفضة'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    await _save(tester, 'share-quality-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(
      tester,
      SignaturesScreen(initialItems: [saved, second]),
    );
    await tester.pumpAndSettle();
    expect(find.text('توقيع العقد'), findsOneWidget);
    expect(find.text('إضافة توقيع'), findsOneWidget);
    await _save(tester, 'signatures-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(
      tester,
      SignatureImportScreen(
        bytes: page,
        startAtCleanup: true,
        initialPreview: signature,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('إزالة الخلفية'), findsOneWidget);
    expect(find.text('الوضوح'), findsOneWidget);
    expect(find.text('أسود'), findsOneWidget);
    await _save(tester, 'signature-cleanup-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(
      tester,
      SignaturePlaceScreen(pageJpeg: page, signaturePng: signature),
    );
    await tester.pumpAndSettle();
    expect(find.text('وضع التوقيع'), findsOneWidget);
    expect(find.text('تثبيت على الصفحة'), findsOneWidget);
    await _save(tester, 'signature-place-ar');
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

Future<void> _save(WidgetTester tester, String name) async {
  final arabic = RegExp(r'[\u0600-\u06FF]');
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    final text = render.text.toPlainText();
    if (!arabic.hasMatch(text)) continue;
    expect(
      render.text.style?.fontFamilyFallback,
      contains(AppTheme.arabicFamily),
      reason: text,
    );
  }
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  final file = File('build/screenshots/phase2/$name.png');
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

Uint8List _signaturePng() {
  final image = img.Image(width: 280, height: 90, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(
    image,
    x1: 16,
    y1: 36,
    x2: 250,
    y2: 48,
    color: img.ColorRgba8(15, 23, 42, 255),
  );
  img.fillRect(
    image,
    x1: 70,
    y1: 18,
    x2: 84,
    y2: 72,
    color: img.ColorRgba8(15, 23, 42, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _pageJpeg() {
  final image = img.Image(width: 480, height: 680, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(244, 242, 236));
  for (var line = 0; line < 12; line++) {
    img.fillRect(
      image,
      x1: 48,
      y1: 70 + line * 40,
      x2: line.isEven ? 400 : 320,
      y2: 82 + line * 40,
      color: img.ColorRgb8(176, 170, 160),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
