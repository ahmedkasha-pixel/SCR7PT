import 'dart:io';
import 'dart:ui' as ui;

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/theme/app_theme.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/features/document/document_screen.dart';
import 'package:docscan/features/folder/folder_screen.dart';
import 'package:docscan/features/scan/page_editor.dart';
import 'package:docscan/features/scan/scan_flow.dart';
import 'package:docscan/features/scan/scan_session.dart';
import 'package:docscan/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

void main() {
  testWidgets('writes screenshots of the main screens', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);

    final empty = (await tester.runAsync(
      () => createHarness(preferences: const {'language_code': 'ar'}),
    ))!;
    addTearDown(empty.dispose);
    await tester.runAsync(() => empty.library.refresh());
    await tester.pumpWidget(_frame(empty.app, 'empty'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-home')), findsOneWidget);
    await _save(tester, 'home-empty-ar');

    final harness = (await tester.runAsync(
      () => createHarness(preferences: const {'language_code': 'ar'}),
    ))!;
    addTearDown(harness.dispose);
    late FolderRecord work;
    late DocumentRecord contract;
    late List<PageRecord> pages;
    await tester.runAsync(() async {
      final created = await harness.documents.createFolder('عمل');
      await harness.documents.createFolder('فواتير');
      contract = await harness.documents.createDocument(
        name: 'عقد الإيجار',
        folderId: created.id,
        pages: [_samplePage()],
      );
      work = (await harness.documents.listFolders()).firstWhere(
        (folder) => folder.id == created.id,
      );
      pages = await harness.documents.pagesFor(contract.id);
      await harness.library.refresh();
    });
    await tester.pumpWidget(_frame(harness.app, 'filled'));
    await tester.pumpAndSettle();
    expect(find.text('عقد الإيجار'), findsOneWidget);
    expect(find.text('عمل'), findsWidgets);
    await _save(tester, 'home-ar');

    _push(tester, FolderScreen(folder: work, initialDocuments: [contract]));
    await tester.pumpAndSettle();
    expect(find.text('عمل'), findsWidgets);
    expect(find.text('عقد الإيجار'), findsOneWidget);
    await _save(tester, 'folder-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(tester, DocumentScreen(document: contract, initialPages: pages));
    await tester.pumpAndSettle();
    expect(find.text('عقد الإيجار'), findsOneWidget);
    await _save(tester, 'document-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(tester, const SettingsScreen());
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);
    await _save(tester, 'settings-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(tester, const ScanFlow());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shutter-button')), findsOneWidget);
    await _save(tester, 'camera-ar');
    _pop(tester);
    await tester.pumpAndSettle();

    _push(
      tester,
      PageEditor(session: _session(), onAddPage: () {}, onDone: () async {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('معاينة'), findsOneWidget);
    await _save(tester, 'editor-ar');
  });
}

Widget _frame(Widget child, String id) {
  return RepaintBoundary(
    key: const Key('shot'),
    child: KeyedSubtree(key: ValueKey(id), child: child),
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
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
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
  final loader = FontLoader(AppTheme.fontFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('assets/fonts/IBMPlexSansArabic-$weight.ttf')
        .readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
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

ScanSession _session() {
  final image = _pageImage();
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 85));
  final session = ScanSession();
  session.pages.add(
    EditablePage(
      id: 'shot-page',
      originalJpeg: jpeg,
      previewJpeg: jpeg,
      corners: Quad.standard,
      width: image.width,
      height: image.height,
    ),
  );
  return session;
}

img.Image _pageImage() {
  final image = img.Image(width: 480, height: 680, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(28, 36, 34));
  img.fillRect(
    image,
    x1: 36,
    y1: 28,
    x2: 444,
    y2: 652,
    color: img.ColorRgb8(248, 246, 240),
  );
  img.fillRect(
    image,
    x1: 70,
    y1: 70,
    x2: 300,
    y2: 96,
    color: img.ColorRgb8(15, 106, 100),
  );
  for (var line = 0; line < 8; line++) {
    img.fillRect(
      image,
      x1: 70,
      y1: 130 + line * 36,
      x2: 400,
      y2: 146 + line * 36,
      color: img.ColorRgb8(190, 186, 176),
    );
  }
  return image;
}
