import 'dart:io';

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/pdf_exporter.dart';
import 'package:docscan/data/db/app_database.dart';
import 'package:docscan/data/models/records.dart';
import 'package:docscan/data/repositories/document_repository.dart';
import 'package:docscan/data/storage/file_store.dart';
import 'package:docscan/features/share/document_sharer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import 'support/sqlite_setup.dart';

void main() {
  setUpAll(ensureSqlite);

  test(
    'pdf share writes a local file and hands it to the share sheet',
    () async {
      final directory = await Directory.systemTemp.createTemp('docscan_share_');
      final files = FileStore(Directory('${directory.path}/files'));
      final repository = DocumentRepository(
        database: AppDatabase(path: '${directory.path}/db.sqlite'),
        files: files,
      );
      final image = img.Image(width: 10, height: 8, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(250, 250, 250));
      final jpeg = img.encodeJpg(image);
      final document = await repository.createDocument(
        name: 'عقد: 2026',
        pages: [
          NewPage(
            id: 'a',
            originalJpeg: jpeg,
            processedJpeg: jpeg,
            filter: PageFilter.original,
            corners: Quad.standard,
          ),
          NewPage(
            id: 'b',
            originalJpeg: jpeg,
            processedJpeg: jpeg,
            filter: PageFilter.grayscale,
            corners: Quad.standard,
          ),
        ],
      );
      final pages = await repository.pagesFor(document.id);
      final shared = <ShareParams>[];
      final sharer = DocumentSharer(
        files: files,
        pdf: PdfExporter(),
        share: (params) async => shared.add(params),
      );

      await sharer.shareDocument(
        document: document,
        pages: pages,
        format: ShareFormat.pdf,
      );
      expect(shared, hasLength(1));
      expect(shared.single.files, hasLength(1));
      expect(shared.single.files!.single.path, endsWith('.pdf'));
      final pdf = await File(shared.single.files!.single.path).readAsBytes();
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

      await sharer.shareDocument(
        document: document,
        pages: pages,
        format: ShareFormat.jpg,
      );
      expect(shared.last.files, hasLength(2));
      expect(shared.last.fileNameOverrides!.first, endsWith('.jpg'));

      await repository.close();
      await directory.delete(recursive: true);
    },
  );
}
