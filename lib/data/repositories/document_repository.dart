import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/geometry/quad.dart';
import '../../core/search/arabic_normalize.dart';
import '../../core/search/content_search.dart';
import '../db/app_database.dart';
import '../models/records.dart';
import '../storage/file_store.dart';

class DocumentRepository {
  DocumentRepository({
    required this._database,
    required this._files,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final FileStore _files;
  final DateTime Function() _clock;
  int _sequence = 0;

  /// Fired after a document's pages, name, or folder change.
  void Function(String documentId)? onDocumentChanged;

  /// Fired when new or edited page images are ready to read.
  void Function(List<PageRecord> pages)? onPagesReady;

  void _changed(String id) {
    onDocumentChanged?.call(id);
  }

  String nextId() => '${_clock().microsecondsSinceEpoch}_${_sequence++}';

  Future<void> close() => _database.close();

  Future<List<FolderRecord>> listFolders() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT f.id, f.name, f.created_at, f.updated_at,
        (SELECT COUNT(*) FROM documents d WHERE d.folder_id = f.id) AS document_count
      FROM folders f
      ORDER BY f.name COLLATE NOCASE
    ''');
    return rows.map(_folderFromRow).toList();
  }

  Future<FolderRecord> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Folder name is required.');
    }
    final db = await _database.database;
    final now = _clock();
    final id = nextId();
    await db.insert('folders', {
      'id': id,
      'name': trimmed,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return FolderRecord(
      id: id,
      name: trimmed,
      createdAt: now,
      updatedAt: now,
      documentCount: 0,
    );
  }

  Future<void> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Folder name is required.');
    }
    final db = await _database.database;
    await db.update(
      'folders',
      {'name': trimmed, 'updated_at': _clock().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes the folder, its documents, and their image files.
  Future<void> deleteFolder(String id) async {
    final documents = await listDocuments(folderId: id);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete('documents', where: 'folder_id = ?', whereArgs: [id]);
      await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
    });
    for (final document in documents) {
      await _files.deleteDocument(document.id);
    }
  }

  Future<List<DocumentRecord>> listDocuments({String? folderId}) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '$_documentSelect WHERE d.folder_id = ? ORDER BY d.updated_at DESC',
      [folderId],
    );
    return rows.map(_documentFromRow).toList();
  }

  Future<List<DocumentRecord>> allDocuments() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '$_documentSelect ORDER BY d.updated_at DESC',
    );
    return rows.map(_documentFromRow).toList();
  }

  Future<List<DocumentRecord>> recentDocuments({int limit = 20}) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '$_documentSelect ORDER BY d.updated_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(_documentFromRow).toList();
  }

  Future<List<DocumentRecord>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return recentDocuments();
    final db = await _database.database;
    final escaped = trimmed
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await db.rawQuery(
      "$_documentSelect WHERE d.name LIKE ? ESCAPE '\\' ORDER BY d.updated_at DESC",
      ['%$escaped%'],
    );
    return rows.map(_documentFromRow).toList();
  }

  Future<DocumentRecord?> documentById(String id) async {
    final db = await _database.database;
    final rows = await db.rawQuery('$_documentSelect WHERE d.id = ?', [id]);
    if (rows.isEmpty) return null;
    return _documentFromRow(rows.first);
  }

  Future<DocumentRecord> createDocument({
    required String name,
    String? folderId,
    required List<NewPage> pages,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Document name is required.');
    }
    if (pages.isEmpty) {
      throw ArgumentError('A document needs at least one page.');
    }
    final db = await _database.database;
    final now = _clock();
    final id = nextId();
    try {
      for (final page in pages) {
        await _files.writeBytes(
          _files.originalPath(id, page.id),
          page.originalJpeg,
        );
        await _files.writeBytes(
          _files.processedPath(id, page.id),
          page.processedJpeg,
        );
      }
      await db.transaction((txn) async {
        await txn.insert('documents', {
          'id': id,
          'folder_id': folderId,
          'name': trimmed,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
        for (var index = 0; index < pages.length; index++) {
          final page = pages[index];
          await txn.insert('pages', {
            'id': page.id,
            'document_id': id,
            'position': index,
            'original_path': _files.originalPath(id, page.id),
            'processed_path': _files.processedPath(id, page.id),
            'filter': page.filter.name,
            'corners': page.corners.toJson(),
            'created_at': now.millisecondsSinceEpoch,
          });
        }
      });
    } catch (error) {
      await _files.deleteDocument(id);
      rethrow;
    }
    final saved = await documentById(id);
    final storedPages = await pagesFor(id);
    onPagesReady?.call(storedPages);
    _changed(id);
    return saved!;
  }

  Future<void> renameDocument(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Document name is required.');
    }
    final db = await _database.database;
    await db.update(
      'documents',
      {'name': trimmed, 'updated_at': _clock().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed(id);
  }

  Future<void> moveDocument(String id, String? folderId) async {
    final db = await _database.database;
    await db.update(
      'documents',
      {'folder_id': folderId, 'updated_at': _clock().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed(id);
  }

  Future<void> deleteDocument(String id) async {
    final db = await _database.database;
    await _deleteFtsForDocument(db, id);
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    await _files.deleteDocument(id);
  }

  Future<List<PageRecord>> pagesFor(String documentId) async {
    final db = await _database.database;
    final rows = await db.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'position ASC',
    );
    return rows.map(_pageFromRow).toList();
  }

  Future<void> updatePage({
    required String pageId,
    required PageFilter filter,
    required Quad corners,
    required List<int> processedJpeg,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'pages',
      where: 'id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Page not found.');
    }
    final row = rows.first;
    final path = row['processed_path'] as String;
    final documentId = row['document_id'] as String;
    await _files.writeBytes(path, processedJpeg);
    final now = _clock().millisecondsSinceEpoch;
    await db.update(
      'pages',
      {'filter': filter.name, 'corners': corners.toJson()},
      where: 'id = ?',
      whereArgs: [pageId],
    );
    await db.update(
      'documents',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [documentId],
    );
    final stored = await pagesFor(documentId);
    PageRecord? updated;
    for (final page in stored) {
      if (page.id == pageId) updated = page;
    }
    if (updated != null) onPagesReady?.call([updated]);
    _changed(documentId);
  }

  /// [orderedIds] is the full page order for the document.
  Future<void> reorderPages(String documentId, List<String> orderedIds) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (var index = 0; index < orderedIds.length; index++) {
        await txn.update(
          'pages',
          {'position': index},
          where: 'id = ? AND document_id = ?',
          whereArgs: [orderedIds[index], documentId],
        );
        await txn.update(
          'page_text',
          {'position': index},
          where: 'page_id = ?',
          whereArgs: [orderedIds[index]],
        );
      }
      await txn.update(
        'documents',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [documentId],
      );
    });
    _changed(documentId);
  }

  /// Returns true when the parent document was removed because it had no pages left.
  Future<bool> deletePage(String pageId) async {
    final db = await _database.database;
    final rows = await db.query(
      'pages',
      where: 'id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final documentId = rows.first['document_id'] as String;
    final original = rows.first['original_path'] as String;
    final processed = rows.first['processed_path'] as String;
    await _deleteFtsForPage(db, pageId);
    await db.delete('pages', where: 'id = ?', whereArgs: [pageId]);
    await _files.deleteFile(original);
    await _files.deleteFile(processed);
    final remaining = await db.query(
      'pages',
      columns: ['id'],
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'position ASC',
    );
    if (remaining.isEmpty) {
      await db.delete('documents', where: 'id = ?', whereArgs: [documentId]);
      await _files.deleteDocument(documentId);
      return true;
    }
    await reorderPages(documentId, [
      for (final row in remaining) row['id'] as String,
    ]);
    return false;
  }

  Future<IndexedPage> savePageText({
    required String pageId,
    required String documentId,
    required int position,
    required String rawText,
  }) async {
    final db = await _database.database;
    final normalized = normalizeForSearch(rawText);
    final digits = extractDigitRuns(rawText).map((run) => run.digits).join(' ');
    await _deleteFtsForPage(db, pageId);
    final rowid = await _insertFtsRow(
      db,
      normalized: normalized,
      pageId: pageId,
      documentId: documentId,
    );
    await db.insert('page_text', {
      'page_id': pageId,
      'document_id': documentId,
      'position': position,
      'raw_text': rawText,
      'normalized': normalized,
      'digits': digits,
      'fts_rowid': rowid,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return IndexedPage(
      pageId: pageId,
      documentId: documentId,
      position: position,
      raw: rawText,
      normalized: normalized,
      digits: digits,
    );
  }

  Future<List<IndexedPage>> indexedPages() async {
    final db = await _database.database;
    final rows = await db.query('page_text', orderBy: 'position ASC');
    return [
      for (final row in rows)
        IndexedPage(
          pageId: row['page_id'] as String,
          documentId: row['document_id'] as String,
          position: row['position'] as int,
          raw: row['raw_text'] as String,
          normalized: row['normalized'] as String,
          digits: row['digits'] as String,
        ),
    ];
  }

  Future<List<PageRecord>> pagesWithoutText() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT p.* FROM pages p
      LEFT JOIN page_text t ON t.page_id = p.id
      WHERE t.page_id IS NULL
      ORDER BY p.created_at ASC
    ''');
    return rows.map(_pageFromRow).toList();
  }

  /// Clears indexed text so a pipeline upgrade re-processes all pages.
  Future<void> clearAllPageText() async {
    final db = await _database.database;
    try {
      await db.delete('page_text');
    } catch (e) {
      debugPrint('clear page_text error: $e');
    }
    try {
      await db.rawDelete('DELETE FROM page_fts');
    } catch (_) {}
  }

  Future<List<String>> pageIdsMatchingFts(String match) async {
    final db = await _database.database;
    try {
      final rows = await db.rawQuery(
        'SELECT page_id FROM page_fts WHERE page_fts MATCH ?',
        [match],
      );
      return [for (final row in rows) row['page_id'] as String];
    } catch (error) {
      debugPrint('FTS match skipped: $error');
      return const [];
    }
  }

  Future<void> _deleteFtsForDocument(Database db, String documentId) async {
    final rows = await db.query(
      'page_text',
      columns: ['fts_rowid'],
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
    for (final row in rows) {
      final rowid = row['fts_rowid'] as int?;
      if (rowid == null) continue;
      await _deleteFtsRow(db, rowid);
    }
    await db.delete(
      'page_text',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> _deleteFtsForPage(Database db, String pageId) async {
    final rows = await db.query(
      'page_text',
      columns: ['fts_rowid'],
      where: 'page_id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final rowid = rows.first['fts_rowid'] as int?;
    if (rowid != null) {
      await _deleteFtsRow(db, rowid);
    }
    await db.delete('page_text', where: 'page_id = ?', whereArgs: [pageId]);
  }

  Future<int?> _insertFtsRow(
    Database db, {
    required String normalized,
    required String pageId,
    required String documentId,
  }) async {
    try {
      return await db.insert('page_fts', {
        'normalized': normalized,
        'page_id': pageId,
        'document_id': documentId,
      });
    } catch (error) {
      debugPrint('FTS insert skipped: $error');
      return null;
    }
  }

  Future<void> _deleteFtsRow(Database db, int rowid) async {
    try {
      await db.rawDelete('DELETE FROM page_fts WHERE rowid = ?', [rowid]);
    } catch (error) {
      debugPrint('FTS delete skipped: $error');
    }
  }
}

const _documentSelect = '''
SELECT d.id, d.folder_id, d.name, d.created_at, d.updated_at,
  (SELECT COUNT(*) FROM pages p WHERE p.document_id = d.id) AS page_count,
  (SELECT p.processed_path FROM pages p
    WHERE p.document_id = d.id
    ORDER BY p.position ASC
    LIMIT 1) AS cover_path
FROM documents d
''';

FolderRecord _folderFromRow(Map<String, Object?> row) {
  return FolderRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    documentCount: row['document_count'] as int,
  );
}

DocumentRecord _documentFromRow(Map<String, Object?> row) {
  return DocumentRecord(
    id: row['id'] as String,
    folderId: row['folder_id'] as String?,
    name: row['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    pageCount: row['page_count'] as int,
    coverPath: row['cover_path'] as String?,
  );
}

PageRecord _pageFromRow(Map<String, Object?> row) {
  return PageRecord(
    id: row['id'] as String,
    documentId: row['document_id'] as String,
    position: row['position'] as int,
    originalPath: row['original_path'] as String,
    processedPath: row['processed_path'] as String,
    filter: PageFilter.values.byName(row['filter'] as String),
    corners: Quad.fromJson(row['corners'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );
}
