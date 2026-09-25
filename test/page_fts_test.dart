import 'dart:io';

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/search/content_search.dart';
import 'package:docscan/data/db/app_database.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/data/repositories/document_repository.dart';
import 'package:docscan/data/storage/file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('v3 database upgrades and keeps documents when FTS is dropped', () async {
    final path = '${directory.path}/legacy.sqlite';
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE documents (
              id TEXT PRIMARY KEY,
              folder_id TEXT,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE pages (
              id TEXT PRIMARY KEY,
              document_id TEXT NOT NULL,
              position INTEGER NOT NULL,
              original_path TEXT NOT NULL,
              processed_path TEXT NOT NULL,
              filter TEXT NOT NULL,
              corners TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE folders (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE signatures (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              image_path TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE signature_placements (
              id TEXT PRIMARY KEY,
              page_id TEXT NOT NULL,
              signature_id TEXT NOT NULL,
              center_x REAL NOT NULL,
              center_y REAL NOT NULL,
              width REAL NOT NULL,
              height REAL NOT NULL,
              rotation REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE drive_links (
              document_id TEXT PRIMARY KEY,
              status TEXT NOT NULL,
              file_ids TEXT NOT NULL,
              progress REAL NOT NULL,
              error TEXT,
              format TEXT NOT NULL,
              compression TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.insert('documents', {
            'id': 'doc-lease',
            'folder_id': null,
            'name': 'عقد الإيجار',
            'created_at': 1,
            'updated_at': 2,
          });
          await db.insert('pages', {
            'id': 'page-1',
            'document_id': 'doc-lease',
            'position': 0,
            'original_path': '/tmp/a.jpg',
            'processed_path': '/tmp/b.jpg',
            'filter': 'original',
            'corners': '{}',
            'created_at': 1,
          });
        },
      ),
    );
    await legacy.close();

    final database = AppDatabase(path: path);
    final upgraded = DocumentRepository(
      database: database,
      files: FileStore(Directory('${directory.path}/files')),
      clock: () => DateTime(2026, 9, 25, 9),
    );
    final documents = await upgraded.allDocuments();
    expect(documents.single.name, 'عقد الإيجار');
    expect(documents.single.pageCount, 1);
    expect(await upgraded.indexedPages(), isEmpty);
    expect(await upgraded.pagesWithoutText(), hasLength(1));

    final db = await database.database;
    await db.execute('DROP TABLE page_fts');
    await upgraded.savePageText(
      pageId: 'page-1',
      documentId: 'doc-lease',
      position: 0,
      rawText: '055-123-4567',
    );
    expect((await upgraded.indexedPages()).single.digits, contains('0551234567'));
    expect(await upgraded.pageIdsMatchingFts('055*'), isEmpty);
    await upgraded.deleteDocument('doc-lease');
    expect(await upgraded.allDocuments(), isEmpty);
    await upgraded.close();
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
