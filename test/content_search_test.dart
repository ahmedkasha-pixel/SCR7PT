import 'package:docscan/core/search/arabic_normalize.dart';
import 'package:docscan/core/search/content_search.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic folding matches راميه to رامية and احمد to أحمد', () {
    expect(normalizeForSearch('رامية'), 'راميه');
    expect(normalizeForSearch('راميه'), 'راميه');
    expect(normalizeForSearch('رَامِيَة'), 'راميه');
    expect(normalizeForSearch('رامـية'), 'راميه');
    expect(normalizeForSearch('أحمد'), 'احمد');
    expect(normalizeForSearch('إحسان'), 'احسان');
    expect(normalizeForSearch('آمنة'), 'امنه');
    expect(normalizeForSearch('على'), 'علي');
    expect(normalizeForSearch('مؤمن'), 'مومن');
    expect(normalizeForSearch('سائل'), 'سايل');
    expect(normalizeForSearch('Invoice'), 'invoice');
  });

  test('digits from either script land in one ASCII run', () {
    expect(
      extractDigitRuns('٠٥٥١٢٣٤٥٦٧').single.digits,
      '0551234567',
    );
    expect(
      extractDigitRuns('۰۵۵۱۲۳۴۵۶۷').single.digits,
      '0551234567',
    );
    expect(
      extractDigitRuns('(055) 123-4567').single.digits,
      '0551234567',
    );
    expect(
      extractDigitRuns('055 123 4567').single.digits,
      '0551234567',
    );
    expect(extractDigitRuns('12.5').single.digits, '125');
    expect(extractDigitRuns('12,5').single.digits, '125');
    expect(extractDigitRuns('12٫5').single.digits, '125');
    expect(extractDigitRuns('1447/03/12').single.digits, '14470312');
    expect(extractDigitRuns('12-03-1447').single.digits, '12031447');
    expect(extractDigitRuns('O551234567').single.digits, '0551234567');
    expect(extractDigitRuns('2O24').single.digits, '2024');
    expect(extractDigitRuns('l2345').single.digits, '12345');
    expect(extractDigitRuns('Hello invoice').map((run) => run.digits), isEmpty);
  });

  test('digit queries match inside longer numbers and ignore separators', () {
    final phone = _page('(055) 123-4567', documentId: 'phone');
    final dashed = _page('055-123-4567', documentId: 'dashed', id: 'dashed');
    final spaced = _page('055 123 4567', documentId: 'spaced', id: 'spaced');
    final flat = _page('0551234567', documentId: 'flat', id: 'flat');
    final indic = _page('٠٥٥١٢٣٤٥٦٧', documentId: 'indic', id: 'indic');
    final dateA = _page('1447/03/12', documentId: 'date-a', id: 'date-a');
    final dateB = _page('12-03-1447', documentId: 'date-b', id: 'date-b');
    final amountDot = _page('12.5', documentId: 'dot', id: 'dot');
    final amountComma = _page('12,5', documentId: 'comma', id: 'comma');

    expect(_ids('4567', [phone]), ['phone']);
    expect(_ids('0551234567', [dashed, spaced, phone]), [
      'dashed',
      'spaced',
      'phone',
    ]);
    expect(_ids('055 123 4567', [flat]), ['flat']);
    expect(_ids('٠٥٥١٢٣٤٥٦٧', [phone]), ['phone']);
    expect(_ids('4567', [indic]), ['indic']);
    expect(_ids('1447/03/12', [dateB]), ['date-b']);
    expect(_ids('12-03-1447', [dateA]), ['date-a']);
    expect(_ids('12.5', [amountComma]), ['comma']);
    expect(_ids('12,5', [amountDot]), ['dot']);
    expect(_ids('12', [flat]), isEmpty);
  });

  test('mixed queries require every term and names rank first', () {
    final named = _doc('a', 'Invoice 2024');
    final content = _doc('b', 'ملاحظات');
    final partial = _doc('c', 'فاتورة فقط');
    final pages = [
      _page('Patient invoice for the year 2024', documentId: 'b', id: 'b0'),
      _page('فاتورة بلا رقم', documentId: 'c', id: 'c0'),
    ];
    final invoice = rankSearch('invoice 2024', [content, named, partial], pages);
    expect(invoice.map((hit) => hit.document.id), ['a', 'b']);
    expect(invoice.first.nameMatch, isTrue);
    expect(invoice.last.nameMatch, isFalse);

    final arabic = rankSearch('فاتورة 2024', [
      _doc('c', 'فاتورة فقط'),
      _doc('e', 'ملف'),
    ], [
      _page('فاتورة رقم ٢٠٢٤', documentId: 'e', id: 'e0'),
    ]);
    expect(arabic.map((hit) => hit.document.id), ['e']);

    final prefix = rankSearch('رام', [
      _doc('n', 'عقد'),
    ], [
      _page('المريضة رامية', documentId: 'n', id: 'n0'),
    ]);
    expect(prefix.single.pageNumber, 1);
    expect(prefix.single.snippet, contains('رامية'));
  });

  test('a content snippet highlights the matched word and the digit span', () {
    final arabic = snippetFor('اسم المريضة رامية بنت أحمد', analyzeQuery('راميه'))!;
    expect(arabic.text.substring(arabic.start, arabic.end), 'رامية');

    final phone = snippetFor('هاتف (055) 123-4567 داخلي', analyzeQuery('4567'))!;
    expect(phone.text.substring(phone.start, phone.end), '4567');
  });

  test('fuzzy and substring matching tolerates OCR errors and ranks exact first', () {
    // 1. Substring inside concatenated words
    final merged = _page('عقد ايجارموحد للطرفين', documentId: 'merged');
    expect(_ids('ايجار', [merged]), ['merged']);

    // 2. OCR typo in Arabic: 'المستاج' matching 'المستاجر'
    final typoAr = _page('بيانات المستاج والطرف الاول', documentId: 'typo-ar');
    expect(_ids('المستاجر', [typoAr]), ['typo-ar']);

    // 3. OCR typo in English: 'invioce' matching 'invoice'
    final typoEn = _page('Total invioce amount 500', documentId: 'typo-en');
    expect(_ids('invoice', [typoEn]), ['typo-en']);

    // 4. Exact matches rank before fuzzy matches
    final exactDoc = _doc('exact', 'وثيقة عادية');
    final fuzzyDoc = _doc('fuzzy', 'وثيقة أخرى');
    final hits = rankSearch('invoice', [fuzzyDoc, exactDoc], [
      _page('invioce payment received', documentId: 'fuzzy', id: 'f0'),
      _page('invoice payment confirmed', documentId: 'exact', id: 'e0'),
    ]);
    expect(hits.map((h) => h.document.id), ['exact', 'fuzzy']);
    expect(hits.first.exactMatch, isTrue);
    expect(hits.last.exactMatch, isFalse);
  });
}

DocumentRecord _doc(String id, String name) {
  return DocumentRecord(
    id: id,
    folderId: null,
    name: name,
    createdAt: DateTime(2026, 9, 25),
    updatedAt: DateTime(2026, 9, 25),
    pageCount: 1,
    coverPath: null,
  );
}

IndexedPage _page(
  String raw, {
  String documentId = 'd',
  String id = 'p',
  int position = 0,
}) {
  return IndexedPage(
    pageId: id,
    documentId: documentId,
    position: position,
    raw: raw,
    normalized: normalizeForSearch(raw),
    digits: extractDigitRuns(raw).map((run) => run.digits).join(' '),
  );
}

List<String> _ids(String query, List<IndexedPage> pages) {
  final documents = [
    for (final id in pages.map((page) => page.documentId).toSet())
      _doc(id, 'ملف $id'),
  ];
  return [
    for (final hit in rankSearch(query, documents, pages)) hit.document.id,
  ];
}
