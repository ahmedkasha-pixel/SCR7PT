// ignore_for_file: avoid_print
import 'dart:io';

import 'package:docscan/core/geometry/quad.dart';
import 'package:docscan/core/processing/document_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Benchmark edge detection corner accuracy (IoU) on realistic test set', () {
    final samples = [
      (
        '1. Shipping Label on Cluttered Desk (User Case)',
        '/tmp/desk_doc_sample.jpg',
        const Quad(
          topLeft: NormPoint(0.08, 0.15),
          topRight: NormPoint(0.78, 0.14),
          bottomRight: NormPoint(0.80, 0.72),
          bottomLeft: NormPoint(0.08, 0.73),
        ),
      ),
      (
        '2. White Table with Torch Glare',
        '/tmp/test_real_2_Light_Table_Torch_Glare.jpg',
        const Quad(
          topLeft: NormPoint(0.12, 0.18),
          topRight: NormPoint(0.82, 0.16),
          bottomRight: NormPoint(0.85, 0.78),
          bottomLeft: NormPoint(0.10, 0.80),
        ),
      ),
      (
        '3. Angled Document on Wood with Clutter',
        '/tmp/test_real_3_Angled_Paper_With_Pen_Mug.jpg',
        const Quad(
          topLeft: NormPoint(0.18, 0.14),
          topRight: NormPoint(0.84, 0.24),
          bottomRight: NormPoint(0.72, 0.84),
          bottomLeft: NormPoint(0.10, 0.72),
        ),
      ),
      (
        '4. Contract on Leather Pad with Sticky Note',
        '/tmp/test_real_4_Dark_Desk_StickyNote.jpg',
        const Quad(
          topLeft: NormPoint(0.15, 0.12),
          topRight: NormPoint(0.80, 0.15),
          bottomRight: NormPoint(0.78, 0.82),
          bottomLeft: NormPoint(0.12, 0.80),
        ),
      ),
      (
        '5. Printed Form on Textured Surface',
        '/tmp/test_real_5_Checkered_Background_Form.jpg',
        const Quad(
          topLeft: NormPoint(0.10, 0.16),
          topRight: NormPoint(0.76, 0.14),
          bottomRight: NormPoint(0.78, 0.86),
          bottomLeft: NormPoint(0.08, 0.85),
        ),
      ),
    ];

    print('\n======================================================');
    print('--- REAL-WORLD DOCUMENT EDGE DETECTION BENCHMARK ---');
    print('Baseline IoU (Old Sobel Hull Detector): 0.8098 (81.0%)');

    var totalIoU = 0.0;
    for (final sample in samples) {
      final name = sample.$1;
      final path = sample.$2;
      final gt = sample.$3;

      final file = File(path);
      if (!file.existsSync()) continue;
      final image = img.decodeImage(file.readAsBytesSync())!;

      final detected = tryDetectQuad(image);
      expect(detected, isNotNull, reason: 'Detection failed on $name');

      final iou = _computeQuadIoU(gt, detected!);
      totalIoU += iou;
      print('$name:');
      print('  GT:       TL=(${gt.topLeft.x.toStringAsFixed(3)}, ${gt.topLeft.y.toStringAsFixed(3)}) TR=(${gt.topRight.x.toStringAsFixed(3)}, ${gt.topRight.y.toStringAsFixed(3)}) BR=(${gt.bottomRight.x.toStringAsFixed(3)}, ${gt.bottomRight.y.toStringAsFixed(3)}) BL=(${gt.bottomLeft.x.toStringAsFixed(3)}, ${gt.bottomLeft.y.toStringAsFixed(3)})');
      print('  Detected: TL=(${detected.topLeft.x.toStringAsFixed(3)}, ${detected.topLeft.y.toStringAsFixed(3)}) TR=(${detected.topRight.x.toStringAsFixed(3)}, ${detected.topRight.y.toStringAsFixed(3)}) BR=(${detected.bottomRight.x.toStringAsFixed(3)}, ${detected.bottomRight.y.toStringAsFixed(3)}) BL=(${detected.bottomLeft.x.toStringAsFixed(3)}, ${detected.bottomLeft.y.toStringAsFixed(3)})');
      print('  IoU with Ground Truth: ${(iou * 100).toStringAsFixed(1)}%');
      expect(iou, greaterThanOrEqualTo(0.90));
    }

    final avgIoU = totalIoU / samples.length;
    print('------------------------------------------------------');
    print('Average IoU with Robust Detector: ${(avgIoU * 100).toStringAsFixed(1)}% (Target >= 90%)');
    print('======================================================\n');

    expect(avgIoU, greaterThanOrEqualTo(0.95));
  });
}

double _computeQuadIoU(Quad q1, Quad q2, {int w = 400, int h = 500}) {
  // Discretize masks to calculate intersection over union
  var inter = 0;
  var union = 0;
  for (var y = 0; y < h; y++) {
    final ny = y / (h - 1);
    for (var x = 0; x < w; x++) {
      final nx = x / (w - 1);
      final p = NormPoint(nx, ny);
      final in1 = _pointInQuad(p, q1);
      final in2 = _pointInQuad(p, q2);
      if (in1 && in2) inter++;
      if (in1 || in2) union++;
    }
  }
  return union > 0 ? (inter / union) : 0.0;
}

bool _pointInQuad(NormPoint p, Quad q) {
  final pts = q.points;
  var inside = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final xi = pts[i].x, yi = pts[i].y;
    final xj = pts[j].x, yj = pts[j].y;
    final intersect = ((yi > p.y) != (yj > p.y)) &&
        (p.x < (xj - xi) * (p.y - yi) / (yj - yi + 1e-9) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}
