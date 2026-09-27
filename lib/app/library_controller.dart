import 'dart:async';

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
  List<SearchHit> searchHits = const [];
  int indexingCurrent = 0;
  int indexingTotal = 0;
  int get indexingPages =>
      indexingTotal > 0 ? (indexingTotal - indexingCurrent + 1) : 0;
  int _generation = 0;
  int _searchGeneration = 0;
  Timer? _searchTimer;

  /// Pages indexed in this session; merged into the next content search.
  final List<IndexedPage> _sessionIndexed = [];

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
      await _applySearch();
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
    if (!searching) {
      _searchTimer?.cancel();
      searchHits = const [];
      searchResults = const [];
      notifyListeners();
      return;
    }
    _rankLocal(const []);
    notifyListeners();
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 160), () {
      unawaited(_applySearch());
    });
  }

  void upsertIndexed(IndexedPage page) {
    _sessionIndexed.removeWhere((item) => item.pageId == page.pageId);
    _sessionIndexed.add(page);
    if (searching) {
      _rankLocal(_sessionIndexed);
      notifyListeners();
    }
  }

  void setIndexing(int current, int total) {
    if (indexingCurrent == current && indexingTotal == total) return;
    indexingCurrent = current;
    indexingTotal = total;
    notifyListeners();
  }

  Future<void> _applySearch() async {
    if (!searching) {
      searchHits = const [];
      searchResults = const [];
      return;
    }
    final generation = ++_searchGeneration;
    final current = query;
    final terms = analyzeQuery(current);
    List<IndexedPage> pages = const [];
    try {
      pages = await documents.pagesMatching(terms);
    } catch (caught) {
      debugPrint('Content search skipped: $caught');
    }
    if (generation != _searchGeneration || current != query) return;
    final byId = {for (final page in pages) page.pageId: page};
    for (final page in _sessionIndexed) {
      byId[page.pageId] = page;
    }
    _rankLocal(byId.values.toList());
    notifyListeners();
  }

  void _rankLocal(List<IndexedPage> pages) {
    if (!searching) {
      searchHits = const [];
      searchResults = const [];
      return;
    }
    searchHits = rankSearch(query, catalog, pages, folders: folders);
    final seen = <String>{};
    searchResults = [
      for (final hit in searchHits)
        if (seen.add(hit.document.id)) hit.document,
    ];
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}
