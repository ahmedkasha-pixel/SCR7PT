import 'package:flutter/foundation.dart';

import '../core/search/content_search.dart';
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
  List<IndexedPage> indexed = const [];
  List<SearchHit> searchHits = const [];
  int indexingCurrent = 0;
  int indexingTotal = 0;
  int get indexingPages => indexingTotal > 0 ? (indexingTotal - indexingCurrent + 1) : 0;
  int _generation = 0;

  /// Pages saved while a refresh was waiting on SQLite.
  final List<IndexedPage> _pendingIndexed = [];

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
      final loadedIndexed = await documents.indexedPages();
      if (generation != _generation) return;
      folders = loadedFolders;
      catalog = loadedCatalog;
      recent = loadedCatalog.take(20).toList();
      final byId = {for (final page in loadedIndexed) page.pageId: page};
      for (final page in _pendingIndexed) {
        byId[page.pageId] = page;
      }
      _pendingIndexed.clear();
      indexed = byId.values.toList();
      _applySearch();
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
    _applySearch();
    notifyListeners();
  }

  void upsertIndexed(IndexedPage page) {
    _pendingIndexed.add(page);
    indexed = [
      for (final existing in indexed)
        if (existing.pageId != page.pageId) existing,
      page,
    ];
    _applySearch();
    notifyListeners();
  }

  void setIndexing(int current, int total) {
    if (indexingCurrent == current && indexingTotal == total) return;
    indexingCurrent = current;
    indexingTotal = total;
    notifyListeners();
  }

  void _applySearch() {
    if (!searching) {
      searchHits = const [];
      searchResults = const [];
      return;
    }
    searchHits = rankSearch(query, catalog, indexed);
    searchResults = [for (final hit in searchHits) hit.document];
  }
}
