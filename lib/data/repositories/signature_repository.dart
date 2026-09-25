import 'dart:typed_data';

import '../../core/processing/signature_extract.dart';
import '../db/app_database.dart';
import '../models/records.dart';
import '../storage/file_store.dart';

class SignatureRepository {
  SignatureRepository({
    required this._database,
    required this._files,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final FileStore _files;
  final DateTime Function() _clock;
  int _sequence = 0;

  String nextId() => '${_clock().microsecondsSinceEpoch}_${_sequence++}';

  Future<List<SignatureRecord>> list() async {
    final db = await _database.database;
    final rows = await db.query('signatures', orderBy: 'created_at DESC');
    return rows.map(_signatureFromRow).toList();
  }

  Future<SignatureRecord> create({
    required String name,
    required Uint8List png,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Signature name is required.');
    }
    final db = await _database.database;
    final now = _clock();
    final id = nextId();
    final path = _files.signaturePath(id);
    await _files.writeBytes(path, tightenSignaturePng(png));
    await db.insert('signatures', {
      'id': id,
      'name': trimmed,
      'image_path': path,
      'created_at': now.millisecondsSinceEpoch,
    });
    return SignatureRecord(
      id: id,
      name: trimmed,
      imagePath: path,
      createdAt: now,
    );
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Signature name is required.');
    }
    final db = await _database.database;
    await db.update(
      'signatures',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'signatures',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await db.delete('signatures', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await _files.deleteFile(rows.first['image_path'] as String);
    }
  }

  Future<List<SignaturePlacement>> placementsForPage(String pageId) async {
    final db = await _database.database;
    final rows = await db.query(
      'signature_placements',
      where: 'page_id = ?',
      whereArgs: [pageId],
    );
    return rows.map(_placementFromRow).toList();
  }

  Future<SignaturePlacement> place({
    required String pageId,
    required String signatureId,
    required double centerX,
    required double centerY,
    required double width,
    required double height,
    required double rotation,
  }) async {
    final db = await _database.database;
    final id = nextId();
    await db.insert('signature_placements', {
      'id': id,
      'page_id': pageId,
      'signature_id': signatureId,
      'center_x': centerX,
      'center_y': centerY,
      'width': width,
      'height': height,
      'rotation': rotation,
    });
    return SignaturePlacement(
      id: id,
      pageId: pageId,
      signatureId: signatureId,
      centerX: centerX,
      centerY: centerY,
      width: width,
      height: height,
      rotation: rotation,
    );
  }

  Future<void> deletePlacement(String id) async {
    final db = await _database.database;
    await db.delete(
      'signature_placements',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

SignatureRecord _signatureFromRow(Map<String, Object?> row) {
  return SignatureRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    imagePath: row['image_path'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );
}

SignaturePlacement _placementFromRow(Map<String, Object?> row) {
  return SignaturePlacement(
    id: row['id'] as String,
    pageId: row['page_id'] as String,
    signatureId: row['signature_id'] as String,
    centerX: (row['center_x'] as num).toDouble(),
    centerY: (row['center_y'] as num).toDouble(),
    width: (row['width'] as num).toDouble(),
    height: (row['height'] as num).toDouble(),
    rotation: (row['rotation'] as num).toDouble(),
  );
}
