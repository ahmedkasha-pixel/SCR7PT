import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan/core/processing/compress.dart';
import 'package:docscan/core/processing/signature_extract.dart';
import 'package:docscan/core/theme/app_theme.dart';
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
import 'support/handwritten.dart';

void main() {
  testWidgets('writes phase 2 Arabic screens', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await _loadFonts();
      await loadHandwritingFont();
    });

    final photo = (await tester.runAsync(
      () => renderBallpointOnPaper(shadow: true, lines: false),
    ))!;
    final extracted = extractSignatureImage(
      photo,
      cleanliness: 0.4,
      ink: SignatureInk.original,
    );
    final signature = Uint8List.fromList(img.encodePng(extracted));
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
    _expectPainted('signatures-ar');
    _expectThumbInk('signatures-ar');
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
    _expectPainted('signature-cleanup-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    final stored = (await tester.runAsync(
      () => File(saved.imagePath).readAsBytes(),
    ))!;
    _push(
      tester,
      SignaturePlaceScreen(pageJpeg: page, signaturePng: stored),
    );
    await tester.pumpAndSettle();
    expect(find.text('وضع التوقيع'), findsOneWidget);
    expect(find.text('تثبيت على الصفحة'), findsOneWidget);
    await _save(tester, 'signature-place-ar');
    _expectPainted('signature-place-ar');
  });
}

void _expectThumbInk(String name) {
  final image = img.decodePng(
    File('build/screenshots/phase2/$name.png').readAsBytesSync(),
  )!;
  final rows = <int>[];
  for (var y = 0; y < (image.height * 0.75).round(); y++) {
    var ink = 0;
    for (var x = 0; x < image.width; x += 2) {
      final pixel = image.getPixel(x, y);
      if (pixel.b > pixel.r + 40 && pixel.b > 90 && pixel.r < 90) ink++;
    }
    if (ink > 12) rows.add(y);
  }
  final bands = <List<int>>[];
  for (final y in rows) {
    if (bands.isEmpty || y > bands.last.last + 6) {
      bands.add([y]);
    } else {
      bands.last.add(y);
    }
  }
  expect(bands.length, greaterThanOrEqualTo(2));
  for (final band in bands.take(2)) {
    expect(band.length, greaterThan(8), reason: 'signature ink is missing');
  }
}

void _expectPainted(String name) {
  final image = img.decodePng(
    File('build/screenshots/phase2/$name.png').readAsBytesSync(),
  )!;
  const background = (15, 23, 42);
  var sampled = 0;
  var different = 0;
  final y0 = (image.height * 0.16).round();
  final y1 = (image.height * 0.62).round();
  for (var y = y0; y < y1; y += 3) {
    for (var x = 12; x < image.width - 12; x += 3) {
      sampled++;
      final pixel = image.getPixel(x, y);
      if ((pixel.r - background.$1).abs() > 12 ||
          (pixel.g - background.$2).abs() > 12 ||
          (pixel.b - background.$3).abs() > 12) {
        different++;
      }
    }
  }
  expect(
    different / sampled,
    greaterThan(0.08),
    reason: '$name preview is still an empty dark panel',
  );
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
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
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
