import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

Future<void> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 8),
  );
}

Future<TestHarness> _boot(
  WidgetTester tester, {
  Map<String, Object> preferences = const {},
  Future<void> Function(TestHarness harness)? seed,
}) async {
  final harness = (await tester.runAsync(
    () => createHarness(preferences: preferences),
  ))!;
  addTearDown(harness.dispose);
  if (seed != null) {
    await tester.runAsync(() => seed(harness));
  }
  await tester.runAsync(() => harness.library.refresh());
  await tester.pumpWidget(harness.app);
  await tester.pump();
  return harness;
}

Future<void> _leaveCamera(WidgetTester tester) async {
  await _settle(tester);
  await tester.tap(find.byKey(const Key('camera-close')));
  await _settle(tester);
}

void main() {
  testWidgets(
    'home is Arabic and right-to-left by default for an Arabic device',
    (tester) async {
      await _boot(tester, preferences: const {'language_code': 'ar'});
      await _settle(tester);
      expect(find.byKey(const Key('shutter-button')), findsOneWidget);
      expect(find.text('SCR7PT'), findsWidgets);
      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        TextDirection.rtl,
      );

      await _leaveCamera(tester);
      expect(find.text('المستندات'), findsWidgets);
      expect(find.text('امسح. رتّب. شارك.'), findsOneWidget);
      expect(find.byKey(const Key('empty-home')), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        TextDirection.rtl,
      );
    },
  );

  testWidgets('folders, recent documents, and search stay in sync', (
    tester,
  ) async {
    await _boot(
      tester,
      preferences: const {'language_code': 'en'},
      seed: (ready) async {
        final work = await ready.documents.createFolder('Work');
        await ready.documents.createFolder('Bills');
        await ready.documents.createDocument(
          name: 'Lease contract',
          folderId: work.id,
          pages: [_page()],
        );
      },
    );
    await _leaveCamera(tester);

    expect(find.text('Documents'), findsWidgets);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Lease contract'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'lease');
    await _settle(tester);
    expect(find.text('Lease contract'), findsOneWidget);
    expect(find.text('Work'), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'missing');
    await _settle(tester);
    expect(find.text('No matching documents'), findsOneWidget);
  });

  testWidgets('settings switches language and the default share format', (
    tester,
  ) async {
    final harness = await _boot(
      tester,
      preferences: const {'language_code': 'ar'},
    );
    await _leaveCamera(tester);

    await tester.tap(find.byKey(const Key('settings-button')));
    await _settle(tester);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('التوقيعات'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Google Drive'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Google Drive'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lang-en')));
    await _settle(tester);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-jpg')));
    await _settle(tester);
    expect(harness.app.settings.settings.shareFormat.name, 'jpg');
    expect(
      AppLocalizations.of(tester.element(find.byType(Scaffold).first)).settings,
      'Settings',
    );
  });
}

NewPage _page() {
  final image = img.Image(width: 8, height: 10, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(230, 230, 230));
  final jpeg = img.encodeJpg(image);
  return NewPage(
    id: 'page-1',
    originalJpeg: jpeg,
    processedJpeg: jpeg,
    filter: PageFilter.original,
    corners: Quad.standard,
  );
}
