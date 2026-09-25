import 'package:sqflite/sqflite.dart';

import '../../data/db/app_database.dart';
import '../../data/models/records.dart';
import 'drive_models.dart';

abstract class DriveLinkStore {
  Future<DriveLink?> get(String documentId);

  Future<List<DriveLink>> all();

  Future<DriveLink?> nextQueued();

  Future<void> put(DriveLink link);

  /// Updates progress only while this attempt is still uploading.
  Future<void> saveProgress(String documentId, DateTime updatedAt, double progress);

  /// An upload that was interrupted is waiting again.
  Future<void> normalizeInterrupted();
}

class MemoryDriveStore implements DriveLinkStore {
  final Map<String, DriveLink> _links = {};

  DriveLink? peek(String documentId) => _links[documentId];

  @override
  Future<DriveLink?> get(String documentId) async => _links[documentId];

  @override
  Future<List<DriveLink>> all() async {
    final items = _links.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return items;
  }

  @override
  Future<DriveLink?> nextQueued() async {
    final waiting = _links.values
        .where((link) => link.status == DriveSyncStatus.queued)
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    if (waiting.isEmpty) return null;
    return waiting.first;
  }

  @override
  Future<void> put(DriveLink link) async {
    _links[link.documentId] = link;
  }

  @override
  Future<void> saveProgress(
    String documentId,
    DateTime updatedAt,
    double progress,
  ) async {
    final current = _links[documentId];
    if (current == null || current.updatedAt != updatedAt) return;
    if (current.status != DriveSyncStatus.uploading) return;
    _links[documentId] = current.copy(progress: progress);
  }

  @override
  Future<void> normalizeInterrupted() async {
    for (final link in _links.values.toList()) {
      if (link.status == DriveSyncStatus.uploading) {
        _links[link.documentId] = link.copy(
          status: DriveSyncStatus.queued,
          progress: 0,
        );
      }
    }
  }
}

class SqliteDriveStore implements DriveLinkStore {
  SqliteDriveStore(this._database);

  final AppDatabase _database;

  @override
  Future<DriveLink?> get(String documentId) async {
    final db = await _database.database;
    final rows = await db.query(
      'drive_links',
      where: 'document_id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<List<DriveLink>> all() async {
    final db = await _database.database;
    final rows = await db.query('drive_links', orderBy: 'updated_at ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<DriveLink?> nextQueued() async {
    final db = await _database.database;
    final rows = await db.query(
      'drive_links',
      where: 'status = ?',
      whereArgs: [DriveSyncStatus.queued.name],
      orderBy: 'updated_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> put(DriveLink link) async {
    final db = await _database.database;
    await db.insert('drive_links', {
      'document_id': link.documentId,
      'status': link.status.name,
      'file_ids': link.fileIds.join('|'),
      'progress': link.progress,
      'error': link.error,
      'format': link.format.name,
      'compression': link.compression.name,
      'updated_at': link.updatedAt.millisecondsSinceEpoch,
    },     conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveProgress(
    String documentId,
    DateTime updatedAt,
    double progress,
  ) async {
    final db = await _database.database;
    await db.update(
      'drive_links',
      {'progress': progress},
      where: 'document_id = ? AND status = ? AND updated_at = ?',
      whereArgs: [
        documentId,
        DriveSyncStatus.uploading.name,
        updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> normalizeInterrupted() async {
    final db = await _database.database;
    await db.update(
      'drive_links',
      {'status': DriveSyncStatus.queued.name, 'progress': 0},
      where: 'status = ?',
      whereArgs: [DriveSyncStatus.uploading.name],
    );
  }

  DriveLink _fromRow(Map<String, Object?> row) {
    final rawIds = row['file_ids'] as String? ?? '';
    return DriveLink(
      documentId: row['document_id'] as String,
      status: DriveSyncStatus.values.byName(row['status'] as String),
      fileIds: rawIds.isEmpty ? const [] : rawIds.split('|'),
      progress: (row['progress'] as num).toDouble(),
      error: row['error'] as String?,
      format: ShareFormat.values.byName(row['format'] as String),
      compression: CompressionLevel.values.byName(row['compression'] as String),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
