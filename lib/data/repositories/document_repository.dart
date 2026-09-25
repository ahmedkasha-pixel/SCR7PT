import '../../core/geometry/quad.dart';
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
  }

  Future<void> moveDocument(String id, String? folderId) async {
    final db = await _database.database;
    await db.update(
      'documents',
      {'folder_id': folderId, 'updated_at': _clock().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDocument(String id) async {
    final db = await _database.database;
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
      }
      await txn.update(
        'documents',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [documentId],
      );
    });
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
