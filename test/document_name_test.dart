import 'package:docscan/core/naming/document_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default document name uses the given clock reading', () {
    expect(
      defaultDocumentName(DateTime(2026, 9, 25, 14, 5)),
      '2026-09-25 14-05',
    );
  });

  test('file stem strips characters that break file names', () {
    expect(safeFileStem('  invoice: march/2026  '), 'invoice march 2026');
    expect(safeFileStem('   '), 'document');
  });
}
