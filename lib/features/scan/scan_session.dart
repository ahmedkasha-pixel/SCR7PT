import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../core/geometry/page_aspect.dart';
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
    this.filter = PageFilter.autoEnhance,
    this.cropping = true,
    this.stale = false,
  });

  final String id;
  final Uint8List originalJpeg;
  Uint8List previewJpeg;
  Quad corners;
  int width;
  int height;
  PageFilter filter;
  bool cropping;
  bool stale;
}

class ScanSession extends ChangeNotifier {
  ScanSession({this.folderId, this.pageSizeMode = PageSizeMode.auto});

  String? folderId;
  PageSizeMode pageSizeMode;

  /// When set, every page is rendered at this size (one document, one size).
  int? forceWidth;
  int? forceHeight;
  final List<EditablePage> pages = [];
  int index = 0;
  bool busy = false;
  int _ids = 0;

  EditablePage? get current =>
      pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];

  Future<void> addBytes(
    Uint8List bytes, {
    bool manual = false,
    Quad? detectedQuad,
  }) async {
    if (pages.length >= AppConfig.maxPagesPerDocument) {
      throw StateError('page-limit');
    }
    // Fast path: use preparePageInstant so the user lands on the crop-adjust
    // screen with zero delay (no blocking heavy full-resolution warp).
    final pageId = '${DateTime.now().microsecondsSinceEpoch}_${_ids++}';
    final initial = preparePageInstant(
      bytes,
      detectedQuad: manual ? null : detectedQuad,
    );

    final editable = EditablePage(
      id: pageId,
      originalJpeg: initial.originalJpeg,
      previewJpeg: initial.previewJpeg,
      corners: Quad.fromList(initial.corners),
      width: initial.width,
      height: initial.height,
      cropping: true,
      stale: false,
    );

    pages.add(editable);
    index = pages.length - 1;
    notifyListeners();

    // In background isolate, generate enhanced preview without blocking UI navigation
    unawaited(
      compute(
        preparePageRequest,
        PrepareRequest(
          bytes,
          pageSizeMode.name,
          detectedQuad: manual ? null : detectedQuad?.toList(),
        ),
      ).then((refined) {
        editable.previewJpeg = refined.previewJpeg;
        editable.width = refined.width;
        editable.height = refined.height;
        // Keep user-edited corners if modified during adjustment
        if (!editable.stale) {
          editable.corners = Quad.fromList(refined.corners);
        }
        notifyListeners();
      }).catchError((_) {}),
    );
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
    if (pages.isEmpty) return;
    final size = _documentSize();
    for (final page in pages) {
      page.cropping = false;
      await _rerender(page, forceWidth: size.width, forceHeight: size.height);
      page.stale = false;
    }
  }

  ({int width, int height}) _documentSize() {
    final forcedW = forceWidth;
    final forcedH = forceHeight;
    if (forcedW != null && forcedH != null) {
      return (width: forcedW, height: forcedH);
    }
    final first = pages.first;
    return pagePixelSize(
      quad: first.corners,
      imageWidth: first.width,
      imageHeight: first.height,
      mode: pageSizeMode,
    );
  }

  Future<void> _rerender(
    EditablePage page, {
    int? forceWidth,
    int? forceHeight,
  }) {
    return _guard(() async {
      page.previewJpeg = await compute(
        renderRequest,
        RenderRequest(
          originalJpeg: page.originalJpeg,
          corners: page.corners.toList(),
          filterName: page.filter.name,
          pageSizeMode: pageSizeMode.name,
          forceWidth: forceWidth,
          forceHeight: forceHeight,
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
