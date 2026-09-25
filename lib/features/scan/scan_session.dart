import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../core/geometry/quad.dart';
import '../../core/processing/document_processor.dart';
import '../../data/models/records.dart';

class EditablePage {
  EditablePage({
    required this.id,
    required this.originalJpeg,
    required this.previewJpeg,
    required this.corners,
    required this.width,
    required this.height,
    this.filter = PageFilter.original,
    this.cropping = true,
    this.stale = false,
  });

  final String id;
  final Uint8List originalJpeg;
  Uint8List previewJpeg;
  Quad corners;
  final int width;
  final int height;
  PageFilter filter;
  bool cropping;
  bool stale;
}

class ScanSession extends ChangeNotifier {
  ScanSession({this.folderId});

  String? folderId;
  final List<EditablePage> pages = [];
  int index = 0;
  bool busy = false;
  int _ids = 0;

  EditablePage? get current =>
      pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];

  Future<void> addBytes(Uint8List bytes) async {
    if (pages.length >= AppConfig.maxPagesPerDocument) {
      throw StateError('page-limit');
    }
    await _guard(() async {
      final prepared = await compute(preparePage, bytes);
      pages.add(
        EditablePage(
          id: '${DateTime.now().microsecondsSinceEpoch}_${_ids++}',
          originalJpeg: prepared.originalJpeg,
          previewJpeg: prepared.previewJpeg,
          corners: Quad.fromList(prepared.corners),
          width: prepared.width,
          height: prepared.height,
        ),
      );
      index = pages.length - 1;
    });
  }

  Future<void> setFilter(PageFilter filter) async {
    final page = current;
    if (page == null) return;
    page.filter = filter;
    page.cropping = false;
    page.stale = false;
    await _rerender(page);
  }

  Future<void> applyCrop() async {
    final page = current;
    if (page == null) return;
    page.cropping = false;
    page.stale = false;
    await _rerender(page);
  }

  void beginCrop() {
    final page = current;
    if (page == null) return;
    page.cropping = true;
    notifyListeners();
  }

  void updateCorner(CropCorner corner, NormPoint point) {
    final page = current;
    if (page == null) return;
    page.corners = page.corners.move(corner, point);
    page.stale = true;
    notifyListeners();
  }

  void resetCorners() {
    final page = current;
    if (page == null) return;
    page.corners = Quad.standard;
    page.stale = true;
    page.cropping = true;
    notifyListeners();
  }

  void select(int next) {
    if (pages.isEmpty) return;
    index = next.clamp(0, pages.length - 1);
    notifyListeners();
  }

  void movePage(int from, int to) {
    if (from < 0 || to < 0 || from >= pages.length || to >= pages.length) {
      return;
    }
    final page = pages.removeAt(from);
    pages.insert(to, page);
    index = to;
    notifyListeners();
  }

  void removeAt(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) return;
    pages.removeAt(pageIndex);
    if (pages.isEmpty) {
      index = 0;
    } else if (index >= pages.length) {
      index = pages.length - 1;
    }
    notifyListeners();
  }

  Future<void> commitPending() async {
    for (final page in pages) {
      if (!page.stale) continue;
      page.cropping = false;
      await _rerender(page);
      page.stale = false;
    }
  }

  Future<void> _rerender(EditablePage page) {
    return _guard(() async {
      page.previewJpeg = await compute(
        renderRequest,
        RenderRequest(
          originalJpeg: page.originalJpeg,
          corners: page.corners.toList(),
          filterName: page.filter.name,
        ),
      );
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
