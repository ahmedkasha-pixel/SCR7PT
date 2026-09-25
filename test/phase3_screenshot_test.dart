import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/features/document/document_screen.dart';
import 'package:docscan/features/drive/drive_models.dart';
import 'package:docscan/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

const _account = DriveAccount(
  email: 'user@gmail.com',
  displayName: 'محمد العتيبي',
);

void main() {
  testWidgets('writes phase 3 Arabic Drive screens', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    final setup = (await tester.runAsync(
      () => createHarness(preferences: const {'language_code': 'ar'}),
    ))!;
    addTearDown(setup.dispose);
    await tester.pumpWidget(
      RepaintBoundary(key: const Key('shot'), child: setup.app),
    );
    await tester.pumpAndSettle();
    _push(
      tester,
      const SettingsScreen(showDriveDeveloperHint: false),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Google Drive غير مُعد بعد'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Google Drive غير مُعد بعد'), findsOneWidget);
    expect(find.textContaining('google_config'), findsNothing);
    expect(
      find.textContaining('تبقى مستنداتك على هذا الجهاز'),
      findsOneWidget,
    );
    await _save(tester, 'drive-settings-setup-ar');

    await tester.pumpWidget(const SizedBox.shrink());
    final signed = (await tester.runAsync(
      () => createHarness(
        preferences: const {'language_code': 'ar'},
        driveConfigured: true,
        driveAccount: const DriveAccount(
          email: 'user@gmail.com',
          displayName: 'محمد العتيبي',
        ),
      ),
    ))!;
    addTearDown(signed.dispose);
    await tester.pumpWidget(
      RepaintBoundary(key: const Key('shot'), child: signed.app),
    );
    await tester.pumpAndSettle();
    _push(tester, const SettingsScreen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('تبقى نسخة على هذا الجهاز، ويمكنك حفظها في Drive متى شئت.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('user@gmail.com'), findsOneWidget);
    expect(find.text('رفع المستندات الجديدة تلقائياً'), findsOneWidget);
    expect(find.text('الرفع عبر Wi-Fi فقط'), findsOneWidget);
    expect(
      find.text('تُحفظ المستندات على هذا الجهاز فقط إلى أن تشاركها.'),
      findsNothing,
    );
    await _save(tester, 'drive-settings-signed-in-ar');

    final document = (await tester.runAsync(
      () => _page(signed, 'عقد الإيجار'),
    ))!;
    await tester.runAsync(
      () => signed.app.drive.saveDocument(
        document.id,
        format: ShareFormat.pdf,
        compression: CompressionLevel.medium,
      ),
    );
    await _openDocument(tester, signed, document);
    expect(find.text('عقد الإيجار'), findsOneWidget);
    expect(find.text('حفظ في Drive'), findsOneWidget);
    expect(find.text('تم الرفع'), findsOneWidget);
    await _save(tester, 'document-drive-ar');

    await tester.pumpWidget(const SizedBox.shrink());
    final failed = (await tester.runAsync(
      () => createHarness(
        preferences: const {'language_code': 'ar'},
        driveConfigured: true,
        driveAccount: _account,
        driveGateway: _ThrowingDriveGateway(),
      ),
    ))!;
    addTearDown(failed.dispose);
    await tester.pumpWidget(
      RepaintBoundary(key: const Key('shot'), child: failed.app),
    );
    await tester.pumpAndSettle();
    final failedDoc = (await tester.runAsync(
      () => _page(failed, 'فاتورة الكهرباء'),
    ))!;
    await tester.runAsync(
      () => failed.app.drive.saveDocument(failedDoc.id),
    );
    await _openDocument(tester, failed, failedDoc);
    expect(find.text('فشل الرفع'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.text('حفظ في Drive'), findsOneWidget);
    await _save(tester, 'document-drive-failed-ar');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final uploadingDoc = (await tester.runAsync(() async {
      final created = await _page(failed, 'عقد العمل');
      await failed.app.drive.seedLink(
        DriveLink(
          documentId: created.id,
          status: DriveSyncStatus.uploading,
          progress: 0.62,
          format: ShareFormat.pdf,
          compression: CompressionLevel.medium,
          updatedAt: DateTime.utc(2026, 9, 25),
        ),
      );
      return created;
    }))!;
    await tester.pump();
    await _openDocument(tester, failed, uploadingDoc);
    expect(find.text('عقد العمل'), findsOneWidget);
    expect(find.text('جارٍ الرفع'), findsOneWidget);
    expect(find.text('حفظ في Drive'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await _save(tester, 'document-drive-uploading-ar');

    final files = [
      'drive-settings-setup-ar',
      'drive-settings-signed-in-ar',
      'document-drive-ar',
      'document-drive-failed-ar',
      'document-drive-uploading-ar',
    ].map((name) => File('build/screenshots/phase3/$name.png')).toList();
    final bytes = (await tester.runAsync(
      () async => [for (final file in files) await file.readAsBytes()],
    ))!;
    for (var i = 0; i < bytes.length; i++) {
      for (var j = i + 1; j < bytes.length; j++) {
        expect(
          _sameBytes(bytes[i], bytes[j]),
          isFalse,
          reason: '${files[i].path} matches ${files[j].path}',
        );
      }
    }
  });
}

Future<DocumentRecord> _page(TestHarness harness, String name) {
  final image = img.Image(width: 480, height: 680, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(244, 242, 236));
  for (var line = 0; line < 10; line++) {
    img.fillRect(
      image,
      x1: 40,
      y1: 70 + line * 48,
      x2: line.isEven ? 420 : 300,
      y2: 84 + line * 48,
      color: img.ColorRgb8(170, 164, 154),
    );
  }
  final jpeg = img.encodeJpg(image, quality: 85);
  return harness.documents.createDocument(
    name: name,
    pages: [
      NewPage(
        id: 'page-$name',
        originalJpeg: jpeg,
        processedJpeg: jpeg,
        filter: PageFilter.original,
        corners: Quad.standard,
      ),
    ],
  );
}

Future<void> _openDocument(
  WidgetTester tester,
  TestHarness harness,
  DocumentRecord document,
) async {
  final pages = (await tester.runAsync(
    () => harness.documents.pagesFor(document.id),
  ))!;
  _push(tester, DocumentScreen(document: document, initialPages: pages));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
}

class _ThrowingDriveGateway extends FakeDriveGateway {
  @override
  Future<List<String>> upload({
    required List<DrivePart> parts,
    required List<String> existingFileIds,
    required String? subfolder,
    required Future<void> Function(double progress) onProgress,
  }) async {
    throw StateError('offline');
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _push(WidgetTester tester, Widget page) {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(MaterialPageRoute<void>(builder: (_) => page));
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  final file = File('build/screenshots/phase3/$name.png');
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
