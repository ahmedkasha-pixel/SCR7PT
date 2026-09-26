import 'dart:typed_data';

import 'package:docscan/core/app_config.dart';
import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/features/document/document_screen.dart';
import 'package:docscan/features/scan/page_editor.dart';
import 'package:docscan/features/scan/scan_session.dart';
import 'package:docscan/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fakes.dart';

Uint8List _jpeg({int width = 60, int height = 80}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(235, 235, 235));
  return img.encodeJpg(image);
}

NewPage _page(String id) {
  final jpeg = _jpeg(width: 8, height: 10);
  return NewPage(
    id: id,
    originalJpeg: jpeg,
    processedJpeg: jpeg,
    filter: PageFilter.original,
    corners: Quad.standard,
  );
}

EditablePage _editable(String id) {
  final jpeg = _jpeg(width: 8, height: 10);
  return EditablePage(
    id: id,
    originalJpeg: jpeg,
    previewJpeg: jpeg,
    corners: Quad.standard,
    width: 8,
    height: 10,
    cropping: false,
  );
}

Future<void> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 8),
  );
}

Future<TestHarness> _boot(
  WidgetTester tester, {
  String language = 'en',
  Future<void> Function(TestHarness harness)? seed,
}) async {
  final harness = (await tester.runAsync(
    () => createHarness(
      preferences: {'language_code': language},
      picture: _jpeg(),
    ),
  ))!;
  addTearDown(harness.dispose);
  if (seed != null) await tester.runAsync(() => seed(harness));
  await tester.runAsync(() => harness.library.refresh());
  await tester.pumpWidget(harness.app);
  await tester.pump();
  await _settle(tester);
  return harness;
}

void _push(WidgetTester tester, Widget page) {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(MaterialPageRoute<void>(builder: (_) => page));
}

Widget _editorApp(ScanSession session, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: PageEditor(
      session: session,
      onAddPage: () => _addTaps++,
      onDone: () async {},
    ),
  );
}

var _addTaps = 0;

void main() {
  setUp(() => _addTaps = 0);

  testWidgets('scan another page appends to the same scan; camera close goes '
      'back to the pages instead of discarding', (tester) async {
    await _boot(tester);

    await tester.tap(find.byKey(const Key('shutter-button')));
    await _settle(tester);

    // Right after capture/crop: a clear "Scan another page" next to Done.
    expect(find.byKey(const Key('add-page')), findsOneWidget);
    expect(find.text('Scan another page'), findsOneWidget);
    expect(find.byKey(const Key('done-button')), findsOneWidget);
    expect(
      find.text('1 of ${AppConfig.maxPagesPerDocument} pages'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('add-page')));
    await _settle(tester);
    expect(find.byKey(const Key('shutter-button')), findsOneWidget);
    expect(find.text('1 page'), findsOneWidget);
    expect(find.text('Back to pages'), findsOneWidget);

    // Leaving the camera keeps the scanned page (no discard dialog).
    await tester.tap(find.byKey(const Key('camera-close')));
    await _settle(tester);
    expect(find.text('Discard this scan?'), findsNothing);
    expect(find.byKey(const Key('add-page')), findsOneWidget);
    expect(
      find.text('1 of ${AppConfig.maxPagesPerDocument} pages'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('add-page')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('shutter-button')));
    await _settle(tester);
    expect(
      find.text('2 of ${AppConfig.maxPagesPerDocument} pages'),
      findsOneWidget,
    );
  });

  testWidgets('editor explains the page limit instead of opening the camera', (
    tester,
  ) async {
    final session = ScanSession(
      existingPages: AppConfig.maxPagesPerDocument - 1,
    )..pages.add(_editable('last'));
    await tester.pumpWidget(_editorApp(session));
    await tester.pump();

    final limit =
        'This document is full (${AppConfig.maxPagesPerDocument} '
        'pages). Save it, then start a new document for more pages.';
    expect(find.text(limit), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-page')));
    await tester.pump();
    expect(_addTaps, 0);
    expect(find.text(limit), findsNWidgets(2)); // caption + snackbar
  });

  testWidgets('scan another is labelled in Arabic and laid out right-to-left', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ScanSession()..pages.add(_editable('p1'));
    await tester.pumpWidget(_editorApp(session, locale: const Locale('ar')));
    await tester.pump();

    expect(find.text('مسح صفحة أخرى'), findsOneWidget);
    expect(
      find.text('1 من ${AppConfig.maxPagesPerDocument} صفحة'),
      findsOneWidget,
    );
    final add = tester.getCenter(find.byKey(const Key('add-page')));
    final done = tester.getCenter(find.byKey(const Key('done-button')));
    expect(add.dx, greaterThan(done.dx)); // start side is the right in RTL
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('add-page')));
    expect(_addTaps, 1);
  });

  testWidgets('a saved document can be reopened and extended with more scans', (
    tester,
  ) async {
    late DocumentRecord document;
    final harness = await _boot(
      tester,
      seed: (ready) async {
        document = await ready.documents.createDocument(
          name: 'Lease contract',
          folderId: null,
          pages: [_page('existing')],
        );
      },
    );
    await tester.tap(find.byKey(const Key('camera-close')));
    await _settle(tester);

    final pages = (await tester.runAsync(
      () => harness.documents.pagesFor(document.id),
    ))!;
    _push(tester, DocumentScreen(document: document, initialPages: pages));
    await _settle(tester);
    expect(find.byKey(const Key('document-add-page-tile')), findsOneWidget);

    await tester.tap(find.byKey(const Key('document-add-pages')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('shutter-button')));
    await _settle(tester);

    expect(find.byKey(const Key('append-banner')), findsOneWidget);
    expect(find.text('Adding pages to “Lease contract”'), findsOneWidget);
    expect(find.text('Add to document'), findsOneWidget);
    expect(
      find.text('2 of ${AppConfig.maxPagesPerDocument} pages'),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('done-button')));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('1 page added').evaluate().isNotEmpty) break;
      }
    });
    await _settle(tester);

    expect(find.text('1 page added'), findsOneWidget);
    final saved = (await tester.runAsync(
      () => harness.documents.pagesFor(document.id),
    ))!;
    expect(saved.map((page) => page.id).first, 'existing');
    expect(saved, hasLength(2));
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.byType(DocumentScreen), findsOneWidget);
  });

  testWidgets('a full document shows a friendly limit message', (tester) async {
    late DocumentRecord document;
    final harness = await _boot(
      tester,
      seed: (ready) async {
        document = await ready.documents.createDocument(
          name: 'Full',
          folderId: null,
          pages: [
            for (var i = 0; i < AppConfig.maxPagesPerDocument; i++)
              _page('p$i'),
          ],
        );
      },
    );
    await tester.tap(find.byKey(const Key('camera-close')));
    await _settle(tester);
    final pages = (await tester.runAsync(
      () => harness.documents.pagesFor(document.id),
    ))!;
    _push(tester, DocumentScreen(document: document, initialPages: pages));
    await _settle(tester);

    await tester.tap(find.byKey(const Key('document-add-pages')));
    await tester.pump();
    expect(find.textContaining('This document is full'), findsOneWidget);
    await _settle(tester);
    expect(find.byKey(const Key('shutter-button')), findsNothing);
  });
}
