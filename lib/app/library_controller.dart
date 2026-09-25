import 'package:flutter/foundation.dart';

import '../data/models/records.dart';
import '../data/repositories/document_repository.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(this.documents);

  final DocumentRepository documents;

  bool loading = true;
  Object? error;
  String query = '';
  List<FolderRecord> folders = const [];
  List<DocumentRecord> recent = const [];
  List<DocumentRecord> catalog = const [];
  List<DocumentRecord> searchResults = const [];
  int _generation = 0;

  bool get searching => query.trim().isNotEmpty;

  Future<void> refresh() async {
    final generation = ++_generation;
    final showSpinner =
        folders.isEmpty && recent.isEmpty && searchResults.isEmpty;
    if (showSpinner) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final loadedFolders = await documents.listFolders();
      final loadedCatalog = await documents.allDocuments();
      if (generation != _generation) return;
      folders = loadedFolders;
      catalog = loadedCatalog;
      recent = loadedCatalog.take(20).toList();
      searchResults = _match(query, loadedCatalog);
      error = null;
    } catch (caught) {
      if (generation != _generation) return;
      error = caught;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void setQuery(String value) {
    query = value;
    searchResults = _match(query, catalog);
    notifyListeners();
  }

  List<DocumentRecord> _match(String value, List<DocumentRecord> source) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];
    return [
      for (final document in source)
        if (document.name.toLowerCase().contains(trimmed)) document,
    ];
  }
}
