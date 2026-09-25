import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/naming/document_name.dart';
import '../../core/processing/pdf_exporter.dart';
import '../../data/models/records.dart';
import '../../data/storage/file_store.dart';

class DocumentSharer {
  DocumentSharer({required this._files, PdfExporter? pdf, this.share})
    : _pdf = pdf ?? PdfExporter();

  final FileStore _files;
  final PdfExporter _pdf;

  /// Test hook. Production uses the platform share sheet.
  final Future<void> Function(ShareParams params)? share;

  Future<void> shareDocument({
    required DocumentRecord document,
    required List<PageRecord> pages,
    required ShareFormat format,
    Rect? origin,
  }) async {
    if (pages.isEmpty) {
      throw StateError('empty');
    }
    final stem = safeFileStem(document.name);
    if (format == ShareFormat.pdf) {
      final images = <Uint8List>[];
      for (final page in pages) {
        images.add(await _files.readBytes(page.processedPath));
      }
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
    for (var i = 0; i < pages.length; i++) {
      final name = pages.length == 1 ? '$stem.jpg' : '$stem-${i + 1}.jpg';
      files.add(
        XFile(pages[i].processedPath, mimeType: 'image/jpeg', name: name),
      );
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

  Future<void> _invoke(ShareParams params) {
    final custom = share;
    if (custom != null) return custom(params);
    return SharePlus.instance.share(params);
  }
}
