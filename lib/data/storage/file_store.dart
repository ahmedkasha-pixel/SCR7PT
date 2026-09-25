import 'dart:io';
import 'dart:typed_data';

class FileStore {
  FileStore(this.root);

  final Directory root;

  String originalPath(String documentId, String pageId) =>
      '${root.path}/documents/$documentId/${pageId}_original.jpg';

  String processedPath(String documentId, String pageId) =>
      '${root.path}/documents/$documentId/$pageId.jpg';

  String exportPath(String fileName) => '${root.path}/exports/$fileName';

  String signaturePath(String id) => '${root.path}/signatures/$id.png';

  Future<void> writeBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  Future<void> deleteDocument(String documentId) async {
    final directory = Directory('${root.path}/documents/$documentId');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
