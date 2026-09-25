import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({required this.path});

  final String path;
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final opened = await openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE documents (
            id TEXT PRIMARY KEY,
            folder_id TEXT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
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
            created_at INTEGER NOT NULL,
            FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
          )
        ''');
        // Phase 2: imported signatures with the paper background removed.
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
            rotation REAL NOT NULL,
            FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE,
            FOREIGN KEY (signature_id) REFERENCES signatures(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_documents_folder ON documents(folder_id)',
        );
        await db.execute(
          'CREATE INDEX idx_documents_updated ON documents(updated_at)',
        );
        await db.execute(
          'CREATE INDEX idx_pages_document ON pages(document_id, position)',
        );
        await db.execute(
          'CREATE INDEX idx_placements_page ON signature_placements(page_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS signature_placements (
              id TEXT PRIMARY KEY,
              page_id TEXT NOT NULL,
              signature_id TEXT NOT NULL,
              center_x REAL NOT NULL,
              center_y REAL NOT NULL,
              width REAL NOT NULL,
              height REAL NOT NULL,
              rotation REAL NOT NULL,
              FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE,
              FOREIGN KEY (signature_id) REFERENCES signatures(id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_placements_page ON signature_placements(page_id)',
          );
        }
      },
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
