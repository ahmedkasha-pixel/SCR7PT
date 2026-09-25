import 'package:docscan/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ui text falls back to IBM Plex and stays at weight 700', () {
    final theme = AppTheme.dark();
    final styles = <TextStyle?>[
      theme.textTheme.headlineMedium,
      theme.textTheme.titleLarge,
      theme.textTheme.titleMedium,
      theme.textTheme.bodyLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.labelLarge,
      theme.filledButtonTheme.style?.textStyle?.resolve({}),
      theme.outlinedButtonTheme.style?.textStyle?.resolve({}),
      theme.textButtonTheme.style?.textStyle?.resolve({}),
      theme.chipTheme.labelStyle,
      theme.chipTheme.secondaryLabelStyle,
      theme.appBarTheme.titleTextStyle,
      theme.appBarTheme.toolbarTextStyle,
      theme.snackBarTheme.contentTextStyle,
      theme.inputDecorationTheme.hintStyle,
      theme.navigationBarTheme.labelTextStyle?.resolve({}),
      AppTheme.text(fontWeight: FontWeight.w800),
    ];

    for (final style in styles) {
      expect(style, isNotNull);
      expect(style!.fontFamily, AppTheme.latinFamily);
      expect(style.fontFamilyFallback, contains(AppTheme.arabicFamily));
      final weight = style.fontWeight;
      if (weight != null) {
        expect(weight.value, lessThanOrEqualTo(700));
      }
    }
  });

  testWidgets('filled buttons and chips paint Arabic with the fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('ar'),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('مشاركة')),
              ChoiceChip(
                label: const Text('الأصل'),
                selected: true,
                onSelected: (_) {},
              ),
              ChoiceChip(
                label: const Text('رمادي'),
                selected: false,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in ['مشاركة', 'الأصل', 'رمادي']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.text.style?.fontFamilyFallback,
        contains(AppTheme.arabicFamily),
        reason: label,
      );
      expect(
        paragraph.text.style?.fontWeight?.value ?? 400,
        lessThanOrEqualTo(700),
        reason: label,
      );
    }
  });
}
