import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/naming/document_name.dart';
import '../../core/processing/compress.dart';
import '../../core/processing/pdf_exporter.dart';
import '../../core/processing/signature_stamp.dart';
import '../../data/models/records.dart';
import '../../data/repositories/signature_repository.dart';
import '../../data/storage/file_store.dart';

class DocumentSharer {
  DocumentSharer({
    required this._files,
    PdfExporter? pdf,
    this.signatures,
    this.share,
  }) : _pdf = pdf ?? PdfExporter();

  final FileStore _files;
  final PdfExporter _pdf;
  final SignatureRepository? signatures;

  /// Test hook. Production uses the platform share sheet.
  final Future<void> Function(ShareParams params)? share;

  final Map<String, ExportSizes> _sizes = {};

  Future<ExportSizes> measure({
    required DocumentRecord document,
    required List<PageRecord> pages,
  }) async {
    final key = await _cacheKey(document, pages);
    final cached = _sizes[key];
    if (cached != null) return cached;
    final prepared = await _payloads(pages);
    final sizes = await compute(
      measureExport,
      MeasureRequest(pages: prepared.pages, stamps: prepared.stamps),
    );
    _sizes[key] = sizes;
    return sizes;
  }

  Future<List<Uint8List>> exportPages({
    required List<PageRecord> pages,
    required CompressionLevel compression,
  }) async {
    final prepared = await _payloads(pages);
    return compute(
      renderExport,
      RenderExportRequest(
        pages: prepared.pages,
        stamps: prepared.stamps,
        levelName: compression.name,
      ),
    );
  }

  Future<void> shareDocument({
    required DocumentRecord document,
    required List<PageRecord> pages,
    required ShareFormat format,
    CompressionLevel compression = CompressionLevel.medium,
    Rect? origin,
  }) async {
    if (pages.isEmpty) {
      throw StateError('empty');
    }
    final stem = safeFileStem(document.name);
    final prepared = await _payloads(pages);
    final images = await compute(
      renderExport,
      RenderExportRequest(
        pages: prepared.pages,
        stamps: prepared.stamps,
        levelName: compression.name,
      ),
    );
    if (format == ShareFormat.pdf) {
      final bytes = await _pdf.build(images);
      final path = _files.exportPath('$stem.pdf');
      await _files.writeBytes(path, bytes);
      await _invoke(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf', name: '$stem.pdf')],
          fileNameOverrides: ['$stem.pdf'],
          title: document.name,
          sharePositionOrigin: origin,
        ),
      );
      return;
    }

    final files = <XFile>[];
    final names = <String>[];
    for (var i = 0; i < images.length; i++) {
      final name = images.length == 1 ? '$stem.jpg' : '$stem-${i + 1}.jpg';
      final path = _files.exportPath(name);
      await _files.writeBytes(path, images[i]);
      files.add(XFile(path, mimeType: 'image/jpeg', name: name));
      names.add(name);
    }
    await _invoke(
      ShareParams(
        files: files,
        fileNameOverrides: names,
        title: document.name,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<({List<Uint8List> pages, List<List<StampPayload>> stamps})> _payloads(
    List<PageRecord> pages,
  ) async {
    final images = <Uint8List>[];
    final stamps = <List<StampPayload>>[];
    for (final page in pages) {
      images.add(await _files.readBytes(page.processedPath));
      stamps.add(await _stampsFor(page.id));
    }
    return (pages: images, stamps: stamps);
  }

  Future<List<StampPayload>> _stampsFor(String pageId) async {
    final repository = signatures;
    if (repository == null) return const [];
    final placements = await repository.placementsForPage(pageId);
    final marks = <StampPayload>[];
    for (final placement in placements) {
      final rows = await repository.list();
      SignatureRecord? match;
      for (final signature in rows) {
        if (signature.id == placement.signatureId) {
          match = signature;
          break;
        }
      }
      if (match == null) continue;
      marks.add(
        StampPayload(
          png: await _files.readBytes(match.imagePath),
          centerX: placement.centerX,
          centerY: placement.centerY,
          width: placement.width,
          height: placement.height,
          rotation: placement.rotation,
        ),
      );
    }
    return marks;
  }

  Future<String> _cacheKey(
    DocumentRecord document,
    List<PageRecord> pages,
  ) async {
    final buffer = StringBuffer(
      '${document.id}:${document.updatedAt.millisecondsSinceEpoch}',
    );
    final repository = signatures;
    for (final page in pages) {
      buffer.write(':${page.id}:${page.processedPath}');
      if (repository == null) continue;
      final placements = await repository.placementsForPage(page.id);
      for (final placement in placements) {
        buffer.write(
          ':${placement.id}:${placement.centerX}:${placement.centerY}:${placement.width}:${placement.height}:${placement.rotation}',
        );
      }
    }
    return buffer.toString();
  }

  Future<void> _invoke(ShareParams params) {
    final custom = share;
    if (custom != null) return custom(params);
    return SharePlus.instance.share(params);
  }
}
