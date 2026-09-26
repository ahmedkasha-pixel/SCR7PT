// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/document_processor.dart';
import 'package:docscan/data/models/records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Benchmark capture path timings: previous blocking path vs new instant path', () async {
    // Generate realistic high-res captured document (3000 x 4000 ~ 12MP JPEG)
    final image = img.Image(width: 3000, height: 4000, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(30, 30, 30));
    img.fillRect(
      image,
      x1: 400,
      y1: 500,
      x2: 2600,
      y2: 3500,
      color: img.ColorRgb8(245, 245, 240),
    );
    final capturedBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
    const detectedQuad = Quad(
      topLeft: NormPoint(0.133, 0.125),
      topRight: NormPoint(0.867, 0.125),
      bottomRight: NormPoint(0.867, 0.875),
      bottomLeft: NormPoint(0.133, 0.875),
    );

    // 1. Simulate Previous Path: Full-resolution decode + edge re-detection + warp + enhancement
    final swPrev = Stopwatch()..start();
    final prevPrepared = preparePageRequest(
      PrepareRequest(
        capturedBytes,
        PageSizeMode.auto.name,
        detectedQuad: detectedQuad.toList(),
      ),
    );
    swPrev.stop();
    final prevDurationMs = swPrev.elapsedMilliseconds;

    // 2. Simulate New Path: Instant metadata decode + immediate navigation to crop-adjust
    final swNew = Stopwatch()..start();
    final instantPrepared = preparePageInstant(
      capturedBytes,
      detectedQuad: detectedQuad,
    );
    swNew.stop();
    final newDurationMs = swNew.elapsedMilliseconds;

    // 3. Verify correctness of both outputs
    expect(prevPrepared.corners, hasLength(8));
    expect(instantPrepared.corners, hasLength(8));
    expect(instantPrepared.width, 3000);
    expect(instantPrepared.height, 4000);

    print('\n======================================================');
    print('--- CAPTURE-TO-CROP-SCREEN LATENCY BENCHMARK ---');
    print('Previous Pipeline (blocking full-res warp & enhance): ${prevDurationMs}ms');
    print('New Optimized Pipeline (instant crop-screen launch):  ${newDurationMs}ms');
    final speedup = (prevDurationMs / mathMax(1, newDurationMs)).toStringAsFixed(1);
    print('Speedup: ${speedup}x faster response on tap');
    print('======================================================\n');

    expect(newDurationMs, lessThan(250));
    expect(newDurationMs, lessThan(prevDurationMs));
  });
}

int mathMax(int a, int b) => a > b ? a : b;
