import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/models/records.dart';

class ExtractRequest {
  ExtractRequest({
    required this.bytes,
    required this.cleanliness,
    required this.inkName,
  });

  final Uint8List bytes;
  final double cleanliness;
  final String inkName;
}

/// Removes paper so the ink is an opaque stroke on a transparent background.
Uint8List extractSignaturePng(ExtractRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('unsupported-image');
  }
  final ink = SignatureInk.values.asNameMap()[request.inkName] ??
      SignatureInk.original;
  final extracted = extractSignatureImage(
    decoded,
    cleanliness: request.cleanliness,
    ink: ink,
  );
  return Uint8List.fromList(img.encodePng(extracted));
}

img.Image extractSignatureImage(
  img.Image source, {
  double cleanliness = 0.55,
  SignatureInk ink = SignatureInk.original,
}) {
  final limited = _limitLongSide(source, 1400);
  final rgb = limited.convert(format: img.Format.uint8, numChannels: 3);
  final width = rgb.width;
  final height = rgb.height;
  final luma = Uint8List(width * height);
  final red = Uint8List(width * height);
  final green = Uint8List(width * height);
  final blue = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = rgb.getPixel(x, y);
      final index = y * width + x;
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      red[index] = r;
      green[index] = g;
      blue[index] = b;
      luma[index] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }
  final background = _paperBackground(luma, width, height);
  final cutoff = 0.10 + cleanliness.clamp(0.0, 1.0) * 0.42;
  const softness = 0.055;
  final alpha = Uint8List(width * height);
  for (var i = 0; i < luma.length; i++) {
    final bg = math.max(1, background[i]);
    final darkness = (1 - luma[i] / bg).clamp(0.0, 1.0);
    final t = ((darkness - (cutoff - softness)) / (softness * 2)).clamp(
      0.0,
      1.0,
    );
    final smooth = t * t * (3 - 2 * t);
    alpha[i] = (smooth * 255).round();
  }
  _removeSpecks(alpha, width, height);
  final output = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      final a = alpha[index];
      final (int r, int g, int b) color = switch (ink) {
        SignatureInk.black => (0, 0, 0),
        SignatureInk.blue => (30, 58, 138),
        SignatureInk.original => (red[index], green[index], blue[index]),
      };
      output.setPixelRgba(x, y, color.$1, color.$2, color.$3, a);
    }
  }
  return _trim(output);
}

Uint8List _paperBackground(Uint8List luma, int width, int height) {
  final long = math.max(width, height);
  final mapLong = long <= 420 ? long : 360;
  final scale = mapLong / long;
  final mapW = math.max(1, (width * scale).round());
  final mapH = math.max(1, (height * scale).round());
  final pooled = Uint8List(mapW * mapH);
  final cellW = width / mapW;
  final cellH = height / mapH;
  for (var y = 0; y < mapH; y++) {
    final y0 = (y * cellH).floor();
    final y1 = math.min(height, ((y + 1) * cellH).ceil());
    for (var x = 0; x < mapW; x++) {
      final x0 = (x * cellW).floor();
      final x1 = math.min(width, ((x + 1) * cellW).ceil());
      var maxV = 0;
      for (var py = y0; py < y1; py++) {
        for (var px = x0; px < x1; px++) {
          final value = luma[py * width + px];
          if (value > maxV) maxV = value;
        }
      }
      pooled[y * mapW + x] = maxV;
    }
  }
  final radius = math.max(8, mapLong ~/ 28);
  final filtered = _maxFilter(pooled, mapW, mapH, radius);
  final full = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final fy = (y + 0.5) * mapH / height - 0.5;
    final y0 = fy.floor().clamp(0, mapH - 1);
    final y1 = math.min(mapH - 1, y0 + 1);
    final ty = (fy - y0).clamp(0.0, 1.0);
    for (var x = 0; x < width; x++) {
      final fx = (x + 0.5) * mapW / width - 0.5;
      final x0 = fx.floor().clamp(0, mapW - 1);
      final x1 = math.min(mapW - 1, x0 + 1);
      final tx = (fx - x0).clamp(0.0, 1.0);
      final value =
          filtered[y0 * mapW + x0] * (1 - tx) * (1 - ty) +
          filtered[y0 * mapW + x1] * tx * (1 - ty) +
          filtered[y1 * mapW + x0] * (1 - tx) * ty +
          filtered[y1 * mapW + x1] * tx * ty;
      full[y * width + x] = value.round().clamp(0, 255);
    }
  }
  return full;
}

Uint8List _maxFilter(Uint8List src, int width, int height, int radius) {
  final temp = Uint8List(src.length);
  final dest = Uint8List(src.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var maxV = 0;
      final x0 = math.max(0, x - radius);
      final x1 = math.min(width - 1, x + radius);
      for (var i = x0; i <= x1; i++) {
        final value = src[y * width + i];
        if (value > maxV) maxV = value;
      }
      temp[y * width + x] = maxV;
    }
  }
  for (var y = 0; y < height; y++) {
    final y0 = math.max(0, y - radius);
    final y1 = math.min(height - 1, y + radius);
    for (var x = 0; x < width; x++) {
      var maxV = 0;
      for (var i = y0; i <= y1; i++) {
        final value = temp[i * width + x];
        if (value > maxV) maxV = value;
      }
      dest[y * width + x] = maxV;
    }
  }
  return dest;
}

void _removeSpecks(Uint8List alpha, int width, int height) {
  final minArea = math.max(12, (width * height * 0.0002).round());
  final seen = Uint8List(alpha.length);
  final queue = ListQueue<int>();
  final component = <int>[];
  for (var start = 0; start < alpha.length; start++) {
    if (seen[start] != 0 || alpha[start] < 40) continue;
    queue.add(start);
    seen[start] = 1;
    component.clear();
    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      component.add(index);
      final x = index % width;
      final y = index ~/ width;
      void visit(int nx, int ny) {
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) return;
        final next = ny * width + nx;
        if (seen[next] != 0 || alpha[next] < 40) return;
        seen[next] = 1;
        queue.add(next);
      }

      visit(x - 1, y);
      visit(x + 1, y);
      visit(x, y - 1);
      visit(x, y + 1);
    }
    if (component.length < minArea) {
      for (final index in component) {
        alpha[index] = 0;
      }
    }
  }
}

img.Image _trim(img.Image source) {
  var minX = source.width;
  var minY = source.height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (source.getPixel(x, y).a < 12) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < minX || maxY < minY) return source;
  const pad = 4;
  final x = math.max(0, minX - pad);
  final y = math.max(0, minY - pad);
  final right = math.min(source.width, maxX + pad + 1);
  final bottom = math.min(source.height, maxY + pad + 1);
  return img.copyCrop(
    source,
    x: x,
    y: y,
    width: math.max(1, right - x),
    height: math.max(1, bottom - y),
  );
}

img.Image _limitLongSide(img.Image source, int maxLong) {
  final long = math.max(source.width, source.height);
  if (long <= maxLong) return source;
  final scale = maxLong / long;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}
