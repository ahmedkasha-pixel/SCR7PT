import 'dart:async';
import 'dart:io';

import '../../core/ocr/page_ocr.dart';
import '../../core/search/content_search.dart';
import '../../data/models/records.dart';
import '../../data/repositories/document_repository.dart';

/// Reads pages one at a time and stores the text on device.
///
/// A short gap between pages keeps a first-launch backfill from pinning a
/// core. Failures stay out of the queue until the next launch.
class PageIndexer {
  PageIndexer({
    required this._documents,
    required this._ocr,
    required this._onIndexed,
    required this._onIndexing,
    this.gap = const Duration(milliseconds: 200),
  });

  final DocumentRepository _documents;
  final PageOcr _ocr;
  final void Function(IndexedPage page) _onIndexed;
  final void Function(int remaining) _onIndexing;
  final Duration gap;

  final List<PageRecord> _queue = [];
  final Set<String> _queued = {};
  final Set<String> _failed = {};
  var _running = false;

  void enqueue(List<PageRecord> pages) {
    for (final page in pages) {
      if (_failed.contains(page.id)) continue;
      final existing = _queue.indexWhere((item) => item.id == page.id);
      if (existing >= 0) {
        _queue[existing] = page;
        continue;
      }
      if (_queued.contains(page.id)) continue;
      _queued.add(page.id);
      _queue.add(page);
    }
    unawaited(_pump());
  }

  Future<void> backfill() async {
    enqueue(await _documents.pagesWithoutText());
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final page = _queue.removeAt(0);
        _queued.remove(page.id);
        _onIndexing(_queue.length + 1);
        try {
          final file = File(page.processedPath);
          if (!file.existsSync()) {
            _failed.add(page.id);
          } else {
            final text = await _ocr.recognize(await file.readAsBytes());
            final stored = await _documents.savePageText(
              pageId: page.id,
              documentId: page.documentId,
              position: page.position,
              rawText: text,
            );
            _onIndexed(stored);
          }
        } catch (_) {
          _failed.add(page.id);
        }
        if (_queue.isNotEmpty && gap > Duration.zero) {
          await Future<void>.delayed(gap);
        }
      }
    } finally {
      _running = false;
      _onIndexing(0);
      if (_queue.isNotEmpty) unawaited(_pump());
    }
  }
}
