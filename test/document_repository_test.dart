import 'dart:io';

import 'package:docscan/core/geometry/quad.dart';
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
    directory = await Directory.systemTemp.createTemp('docscan_repo_');
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

  NewPage samplePage(String id) {
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

  test(
    'folders and documents can be created, renamed, moved, and searched',
    () async {
      final work = await repository.createFolder('العمل');
      final bills = await repository.createFolder('الفواتير');
      await repository.renameFolder(bills.id, 'فواتير 2026');

      final first = await repository.createDocument(
        name: 'عقد إيجار',
        folderId: work.id,
        pages: [samplePage('p1'), samplePage('p2')],
      );
      await repository.createDocument(
        name: 'Invoice March',
        folderId: bills.id,
        pages: [samplePage('p3')],
      );

      final folders = await repository.listFolders();
      expect(folders.map((folder) => folder.name), contains('فواتير 2026'));
      expect(
        folders.firstWhere((folder) => folder.id == work.id).documentCount,
        1,
      );

      final inWork = await repository.listDocuments(folderId: work.id);
      expect(inWork.single.name, 'عقد إيجار');
      expect(inWork.single.pageCount, 2);
      expect(File(inWork.single.coverPath!).existsSync(), isTrue);

      final found = await repository.search('inv');
      expect(found.single.name, 'Invoice March');
      final arabic = await repository.search('إيجار');
      expect(arabic.single.id, first.id);

      await repository.renameDocument(first.id, 'عقد جديد');
      await repository.moveDocument(first.id, bills.id);
      final moved = await repository.documentById(first.id);
      expect(moved!.name, 'عقد جديد');
      expect(moved.folderId, bills.id);
      expect((await repository.listDocuments(folderId: work.id)), isEmpty);

      final pages = await repository.pagesFor(first.id);
      expect(pages, hasLength(2));
      await repository.reorderPages(first.id, [pages[1].id, pages[0].id]);
      final reordered = await repository.pagesFor(first.id);
      expect(reordered.first.id, pages[1].id);
      expect(reordered.first.position, 0);
    },
  );

  test('deleting a folder removes its documents and files', () async {
    final folder = await repository.createFolder('مؤقت');
    final document = await repository.createDocument(
      name: 'ورقة',
      folderId: folder.id,
      pages: [samplePage('gone')],
    );
    final cover = document.coverPath!;
    expect(File(cover).existsSync(), isTrue);

    await repository.deleteFolder(folder.id);
    expect(await repository.documentById(document.id), isNull);
    expect(await repository.listFolders(), isEmpty);
    expect(File(cover).existsSync(), isFalse);
  });

  test('updating a page rewrites the processed image', () async {
    final document = await repository.createDocument(
      name: 'note',
      pages: [samplePage('edit')],
    );
    final original = (await repository.pagesFor(document.id)).single;
    final updated = img.encodeJpg(
      img.Image(width: 4, height: 4, numChannels: 3)
        ..setPixelRgb(0, 0, 9, 9, 9),
    );
    await repository.updatePage(
      pageId: original.id,
      filter: PageFilter.grayscale,
      corners: Quad.fullFrame,
      processedJpeg: updated,
    );
    final page = (await repository.pagesFor(document.id)).single;
    expect(page.filter, PageFilter.grayscale);
    expect(page.corners.topLeft.x, 0);
    expect(File(page.processedPath).readAsBytesSync(), updated);
  });

  test('rejects an empty document', () {
    expect(
      repository.createDocument(name: 'empty', pages: const []),
      throwsArgumentError,
    );
  });
}
