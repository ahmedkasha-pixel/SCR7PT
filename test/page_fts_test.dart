import 'dart:io';

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/search/content_search.dart';
import 'package:docscan/data/db/app_database.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/data/repositories/document_repository.dart';
import 'package:docscan/data/storage/file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/sqlite_setup.dart';

void main() {
  setUpAll(ensureSqlite);

  late Directory directory;
  late DocumentRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('docscan_fts_');
    repository = DocumentRepository(
      database: AppDatabase(path: '${directory.path}/db.sqlite'),
      files: FileStore(Directory('${directory.path}/files')),
      clock: () => DateTime(2026, 9, 25, 9),
    );
  });

  tearDown(() async {
    await repository.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('FTS prefix finds folded Arabic and the digit column ignores separators', () async {
    final document = await repository.createDocument(
      name: 'تقرير المختبر',
      pages: [_page('p1'), _page('p2')],
    );
    final pages = await repository.pagesFor(document.id);
    await repository.savePageText(
      pageId: pages[1].id,
      documentId: document.id,
      position: pages[1].position,
      rawText: 'المريضة رامية  هاتف (055) 123-4567  تاريخ 12-03-1447',
    );

    final match = ftsPrefixQuery(analyzeQuery('راميه'));
    expect(match, 'راميه*');
    expect(await repository.pageIdsMatchingFts(match!), [pages[1].id]);
    expect(await repository.pageIdsMatchingFts('رام*'), [pages[1].id]);

    final indexed = await repository.indexedPages();
    expect(indexed.single.position, 1);
    expect(indexed.single.normalized, contains('راميه'));
    expect(indexed.single.digits, contains('0551234567'));
    expect(indexed.single.digits, contains('12031447'));

    await repository.deleteDocument(document.id);
    expect(await repository.pageIdsMatchingFts('رام*'), isEmpty);
    expect(await repository.indexedPages(), isEmpty);
  });
}

NewPage _page(String id) {
  final image = img.Image(width: 8, height: 6, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(240, 240, 240));
  final jpeg = img.encodeJpg(image);
  return NewPage(
    id: id,
    originalJpeg: jpeg,
    processedJpeg: jpeg,
    filter: PageFilter.original,
    corners: Quad.standard,
  );
}
