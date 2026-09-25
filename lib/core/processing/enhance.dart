import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Flattens shadows while keeping ink dark and coloured marks coloured.
///
/// The background is a luminance map: max-pooled to a few hundred pixels,
/// closed with a text-stroke kernel, then blurred by a pixel or two. Every
/// channel is divided by that same luminance gain. A second pass compares
/// each pixel to the local paper again, clips the white point near 0.92, and
/// stretches neutral tones toward black.
img.Image autoEnhance(img.Image source) {
  final rgb = source.convert(format: img.Format.uint8, numChannels: 3);
  final lifted = _lumaNormalize(rgb, finalize: false);
  return _lumaNormalize(lifted, finalize: true);
}

/// Shadow-normalized grayscale. Paper is even; colour is discarded.
img.Image grayscaleNormalized(img.Image source) {
  return _toGray(autoEnhance(source));
}

/// Adaptive black-and-white on the shadow-normalized page.
///
/// Sauvola runs on a downscaled luminance map (window ≈ 1/20 of the width)
/// so a dark shadow does not become a solid black region.
img.Image blackAndWhiteAdaptive(img.Image source) {
  final divided = _divideByIllumination(source);
  final view = _Rgb(divided);
  final luma = Uint8List(view.width * view.height);
  for (var i = 0; i < luma.length; i++) {
    final index = i * view.channels;
    luma[i] = _luma(
      view.bytes[index],
      view.bytes[index + 1],
      view.bytes[index + 2],
    );
  }
  final threshold = _sauvolaThreshold(luma, view.width, view.height);
  final output = img.Image(
    width: view.width,
    height: view.height,
    numChannels: 3,
  );
  final dest = _Rgb(output);
  final mapW = threshold.width;
  final mapH = threshold.height;
  for (var y = 0; y < view.height; y++) {
    final fy = (y + 0.5) * mapH / view.height - 0.5;
    for (var x = 0; x < view.width; x++) {
      final fx = (x + 0.5) * mapW / view.width - 0.5;
      final limit = _sample(threshold.values, mapW, mapH, fx, fy);
      final ink = luma[y * view.width + x] < limit ? 0 : 255;
      dest.set(x, y, ink, ink, ink);
    }
  }
  return output;
}

img.Image _divideByIllumination(img.Image source) {
  final view = _Rgb(source);
  final longEdge = math.max(view.width, view.height);
  final mapLong = longEdge < 48 ? longEdge : math.min(420, longEdge);
  final scale = mapLong / longEdge;
  final mapW = math.max(1, (view.width * scale).round());
  final mapH = math.max(1, (view.height * scale).round());
  final radius = math.max(2, math.min(mapW, mapH) ~/ 32);
  final blur = math.max(3, math.min(mapW, mapH) ~/ 8);

  final maps = <Uint8List>[];
  for (var channel = 0; channel < 3; channel++) {
    final plane = _downsample(view, channel, mapW, mapH);
    final closed = _minFilter(
      _maxFilter(plane, mapW, mapH, radius),
      mapW,
      mapH,
      radius,
    );
    maps.add(_boxBlur(closed, mapW, mapH, blur, passes: 3));
  }

  final output = img.Image(
    width: view.width,
    height: view.height,
    numChannels: 3,
  );
  final dest = _Rgb(output);
  for (var y = 0; y < view.height; y++) {
    final fy = (y + 0.5) * mapH / view.height - 0.5;
    for (var x = 0; x < view.width; x++) {
      final fx = (x + 0.5) * mapW / view.width - 0.5;
      for (var channel = 0; channel < 3; channel++) {
        final illum = math.max(16, _sample(maps[channel], mapW, mapH, fx, fy));
        final value = (view.channel(x, y, channel) * 255 / illum).round();
        dest.setChannel(x, y, channel, value);
      }
    }
  }
  return output;
}

/// One illumination pass. [finalize] clips paper to white and darkens ink.
img.Image _lumaNormalize(img.Image source, {required bool finalize}) {
  final view = _Rgb(source);
  final luma = Uint8List(view.width * view.height);
  for (var y = 0; y < view.height; y++) {
    for (var x = 0; x < view.width; x++) {
      luma[y * view.width + x] = view.luma(x, y);
    }
  }
  final map = _textScaleBackground(luma, view.width, view.height);
  final output = img.Image(
    width: view.width,
    height: view.height,
    numChannels: 3,
  );
  final dest = _Rgb(output);
  for (var y = 0; y < view.height; y++) {
    final fy = (y + 0.5) * map.height / view.height - 0.5;
    for (var x = 0; x < view.width; x++) {
      final fx = (x + 0.5) * map.width / view.width - 0.5;
      final bg = math.max(
        8,
        _sample(map.values, map.width, map.height, fx, fy),
      );
      final red = view.r(x, y);
      final green = view.g(x, y);
      final blue = view.b(x, y);
      final tone = math.max(1, _luma(red, green, blue));
      final chroma =
          math.max(red, math.max(green, blue)) -
          math.min(red, math.min(green, blue));
      final ratio = tone / bg;
      final double outLuma;
      if (finalize && chroma < 72 && ratio >= 0.92) {
        dest.set(x, y, 255, 255, 255);
        continue;
      } else if (finalize && chroma < 72) {
        final t = (ratio / 0.92).clamp(0.0, 1.0);
        outLuma = math.pow(t, 2.6) * 255;
      } else {
        outLuma = (tone * 255 / bg).clamp(0.0, 255.0);
      }
      final gain = outLuma / tone;
      dest.set(
        x,
        y,
        (red * gain).round(),
        (green * gain).round(),
        (blue * gain).round(),
      );
    }
  }
  return output;
}

/// Luminance background at long side 256–400. Closing radius matches a text
/// stroke; the blur is only a couple of map pixels so a shadow edge stays put.
_Illum _textScaleBackground(Uint8List luma, int width, int height) {
  final longEdge = math.max(width, height);
  final mapLong = longEdge <= 400 ? longEdge : 360;
  final scale = mapLong / longEdge;
  final mapW = math.max(1, (width * scale).round());
  final mapH = math.max(1, (height * scale).round());
  final pooled = _downsampleMaxLuma(luma, width, height, mapW, mapH);
  // ~14 px on the original is enough to close strokes without bridging a shadow.
  final radius = math.max(2, (14 * mapLong / longEdge).round());
  final closed = _minFilter(
    _maxFilter(pooled, mapW, mapH, radius),
    mapW,
    mapH,
    radius,
  );
  final blurred = _boxBlur(closed, mapW, mapH, 1);
  return _Illum(blurred, mapW, mapH);
}

class _Illum {
  _Illum(this.values, this.width, this.height);
  final Uint8List values;
  final int width;
  final int height;
}

img.Image _toGray(img.Image source) {
  final view = _Rgb(source);
  final output = img.Image(
    width: view.width,
    height: view.height,
    numChannels: 3,
  );
  final dest = _Rgb(output);
  for (var y = 0; y < view.height; y++) {
    for (var x = 0; x < view.width; x++) {
      final value = view.luma(x, y);
      dest.set(x, y, value, value, value);
    }
  }
  return output;
}

class _ThresholdMap {
  _ThresholdMap(this.values, this.width, this.height);
  final Uint8List values;
  final int width;
  final int height;
}

_ThresholdMap _sauvolaThreshold(Uint8List luma, int width, int height) {
  final longEdge = math.max(width, height);
  final mapLong = longEdge < 48 ? longEdge : math.min(960, longEdge);
  final scale = mapLong / longEdge;
  final mapW = math.max(1, (width * scale).round());
  final mapH = math.max(1, (height * scale).round());
  final small = _downsampleLuma(luma, width, height, mapW, mapH);
  final window = math.max(15, math.min(mapW, mapH) ~/ 20);
  final radius = window ~/ 2;
  const k = 0.34;
  const dynamicRange = 128.0;

  final integral = _Integral(small, mapW, mapH);
  final values = Uint8List(mapW * mapH);
  for (var y = 0; y < mapH; y++) {
    final y0 = math.max(0, y - radius);
    final y1 = math.min(mapH - 1, y + radius);
    for (var x = 0; x < mapW; x++) {
      final x0 = math.max(0, x - radius);
      final x1 = math.min(mapW - 1, x + radius);
      final area = (x1 - x0 + 1) * (y1 - y0 + 1);
      final sum = integral.rect(x0, y0, x1, y1);
      final sumSq = integral.rectSquares(x0, y0, x1, y1);
      final mean = sum / area;
      final variance = math.max(0, sumSq / area - mean * mean);
      final std = math.sqrt(variance);
      final threshold = mean * (1 + k * (std / dynamicRange - 1));
      values[y * mapW + x] = threshold.round().clamp(0, 255);
    }
  }
  return _ThresholdMap(values, mapW, mapH);
}

Uint8List _downsample(_Rgb view, int channel, int mapW, int mapH) {
  final dest = Uint8List(mapW * mapH);
  for (var y = 0; y < mapH; y++) {
    final y0 = (y * view.height / mapH).floor();
    final y1 = math.max(y0 + 1, ((y + 1) * view.height / mapH).ceil());
    final yEnd = math.min(view.height, y1);
    for (var x = 0; x < mapW; x++) {
      final x0 = (x * view.width / mapW).floor();
      final x1 = math.max(x0 + 1, ((x + 1) * view.width / mapW).ceil());
      final xEnd = math.min(view.width, x1);
      var sum = 0;
      var count = 0;
      for (var py = y0; py < yEnd; py++) {
        for (var px = x0; px < xEnd; px++) {
          sum += view.channel(px, py, channel);
          count++;
        }
      }
      dest[y * mapW + x] = count == 0 ? 0 : (sum / count).round();
    }
  }
  return dest;
}

Uint8List _downsampleMaxLuma(
  Uint8List src,
  int width,
  int height,
  int mapW,
  int mapH,
) {
  final dest = Uint8List(mapW * mapH);
  for (var y = 0; y < mapH; y++) {
    final y0 = (y * height / mapH).floor();
    final y1 = math.min(
      height,
      math.max(y0 + 1, ((y + 1) * height / mapH).ceil()),
    );
    for (var x = 0; x < mapW; x++) {
      final x0 = (x * width / mapW).floor();
      final x1 = math.min(
        width,
        math.max(x0 + 1, ((x + 1) * width / mapW).ceil()),
      );
      var maxValue = 0;
      for (var py = y0; py < y1; py++) {
        for (var px = x0; px < x1; px++) {
          final value = src[py * width + px];
          if (value > maxValue) maxValue = value;
        }
      }
      dest[y * mapW + x] = maxValue;
    }
  }
  return dest;
}

Uint8List _downsampleLuma(
  Uint8List src,
  int width,
  int height,
  int mapW,
  int mapH,
) {
  final dest = Uint8List(mapW * mapH);
  for (var y = 0; y < mapH; y++) {
    final y0 = (y * height / mapH).floor();
    final y1 = math.min(
      height,
      math.max(y0 + 1, ((y + 1) * height / mapH).ceil()),
    );
    for (var x = 0; x < mapW; x++) {
      final x0 = (x * width / mapW).floor();
      final x1 = math.min(
        width,
        math.max(x0 + 1, ((x + 1) * width / mapW).ceil()),
      );
      var sum = 0;
      var count = 0;
      for (var py = y0; py < y1; py++) {
        for (var px = x0; px < x1; px++) {
          sum += src[py * width + px];
          count++;
        }
      }
      dest[y * mapW + x] = count == 0 ? 0 : (sum / count).round();
    }
  }
  return dest;
}

Uint8List _maxFilter(Uint8List src, int width, int height, int radius) {
  return _extremum(src, width, height, radius, maximum: true);
}

Uint8List _minFilter(Uint8List src, int width, int height, int radius) {
  return _extremum(src, width, height, radius, maximum: false);
}

Uint8List _extremum(
  Uint8List src,
  int width,
  int height,
  int radius, {
  required bool maximum,
}) {
  final temp = Uint8List(src.length);
  final dest = Uint8List(src.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final x0 = math.max(0, x - radius);
      final x1 = math.min(width - 1, x + radius);
      var value = src[y * width + x0];
      for (var i = x0 + 1; i <= x1; i++) {
        final sample = src[y * width + i];
        if (maximum ? sample > value : sample < value) value = sample;
      }
      temp[y * width + x] = value;
    }
  }
  for (var y = 0; y < height; y++) {
    final y0 = math.max(0, y - radius);
    final y1 = math.min(height - 1, y + radius);
    for (var x = 0; x < width; x++) {
      var value = temp[y0 * width + x];
      for (var i = y0 + 1; i <= y1; i++) {
        final sample = temp[i * width + x];
        if (maximum ? sample > value : sample < value) value = sample;
      }
      dest[y * width + x] = value;
    }
  }
  return dest;
}

Uint8List _boxBlur(
  Uint8List src,
  int width,
  int height,
  int radius, {
  int passes = 1,
}) {
  var current = src;
  for (var pass = 0; pass < passes; pass++) {
    final temp = Uint8List(current.length);
    final dest = Uint8List(current.length);
    for (var y = 0; y < height; y++) {
      var sum = 0;
      var count = 0;
      for (var x = 0; x < width; x++) {
        final add = math.min(width - 1, x + radius);
        final remove = x - radius - 1;
        if (x == 0) {
          final end = math.min(width - 1, radius);
          for (var i = 0; i <= end; i++) {
            sum += current[y * width + i];
            count++;
          }
        } else {
          sum += current[y * width + add];
          count++;
          if (remove >= 0) {
            sum -= current[y * width + remove];
            count--;
          }
        }
        temp[y * width + x] = (sum / count).round();
      }
    }
    for (var x = 0; x < width; x++) {
      var sum = 0;
      var count = 0;
      for (var y = 0; y < height; y++) {
        final add = math.min(height - 1, y + radius);
        final remove = y - radius - 1;
        if (y == 0) {
          final end = math.min(height - 1, radius);
          for (var i = 0; i <= end; i++) {
            sum += temp[i * width + x];
            count++;
          }
        } else {
          sum += temp[add * width + x];
          count++;
          if (remove >= 0) {
            sum -= temp[remove * width + x];
            count--;
          }
        }
        dest[y * width + x] = (sum / count).round();
      }
    }
    current = dest;
  }
  return current;
}

int _sample(Uint8List map, int width, int height, double x, double y) {
  final clampedX = x.clamp(0, width - 1).toDouble();
  final clampedY = y.clamp(0, height - 1).toDouble();
  final x0 = clampedX.floor();
  final y0 = clampedY.floor();
  final x1 = math.min(x0 + 1, width - 1);
  final y1 = math.min(y0 + 1, height - 1);
  final dx = clampedX - x0;
  final dy = clampedY - y0;
  final value =
      map[y0 * width + x0] * (1 - dx) * (1 - dy) +
      map[y0 * width + x1] * dx * (1 - dy) +
      map[y1 * width + x0] * (1 - dx) * dy +
      map[y1 * width + x1] * dx * dy;
  return value.round().clamp(0, 255);
}

int _luma(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round();

class _Integral {
  _Integral(Uint8List src, int width, int height)
    : stride = width + 1,
      _sum = Int64List((width + 1) * (height + 1)),
      _sumSq = Int64List((width + 1) * (height + 1)) {
    for (var y = 1; y <= height; y++) {
      var row = 0;
      var rowSq = 0;
      for (var x = 1; x <= width; x++) {
        final value = src[(y - 1) * width + (x - 1)];
        row += value;
        rowSq += value * value;
        final above = (y - 1) * stride + x;
        _sum[y * stride + x] = _sum[above] + row;
        _sumSq[y * stride + x] = _sumSq[above] + rowSq;
      }
    }
  }

  final int stride;
  final Int64List _sum;
  final Int64List _sumSq;

  int rect(int x0, int y0, int x1, int y1) => _rect(_sum, x0, y0, x1, y1);
  int rectSquares(int x0, int y0, int x1, int y1) =>
      _rect(_sumSq, x0, y0, x1, y1);

  int _rect(Int64List table, int x0, int y0, int x1, int y1) {
    final a = table[y0 * stride + x0];
    final b = table[y0 * stride + (x1 + 1)];
    final c = table[(y1 + 1) * stride + x0];
    final d = table[(y1 + 1) * stride + (x1 + 1)];
    return d - b - c + a;
  }
}

class _Rgb {
  _Rgb(this.image)
    : bytes = image.toUint8List(),
      width = image.width,
      height = image.height,
      channels = image.numChannels;

  final img.Image image;
  final Uint8List bytes;
  final int width;
  final int height;
  final int channels;

  int _index(int x, int y) => (y * width + x) * channels;

  int channel(int x, int y, int channel) => bytes[_index(x, y) + channel];
  int r(int x, int y) => channel(x, y, 0);
  int g(int x, int y) => channel(x, y, 1);
  int b(int x, int y) => channel(x, y, 2);
  int luma(int x, int y) => _luma(r(x, y), g(x, y), b(x, y));

  void set(int x, int y, int red, int green, int blue) {
    final index = _index(x, y);
    bytes[index] = red.clamp(0, 255);
    bytes[index + 1] = green.clamp(0, 255);
    bytes[index + 2] = blue.clamp(0, 255);
  }

  void setChannel(int x, int y, int channel, int value) {
    bytes[_index(x, y) + channel] = value.clamp(0, 255);
  }
}
