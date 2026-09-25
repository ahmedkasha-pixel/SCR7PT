import 'package:docscan/core/geometry/quad.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unordered points become a clockwise page quad', () {
    final quad = Quad.fromUnordered(const [
      NormPoint(0.8, 0.8),
      NormPoint(0.2, 0.2),
      NormPoint(0.8, 0.2),
      NormPoint(0.2, 0.8),
    ]);
    expect(quad.topLeft.x, lessThan(quad.topRight.x));
    expect(quad.topLeft.y, lessThan(quad.bottomLeft.y));
    expect(quad.bottomRight.x, greaterThan(quad.bottomLeft.x));
  });

  test('json round trip keeps the corners', () {
    const original = Quad(
      topLeft: NormPoint(0.1, 0.2),
      topRight: NormPoint(0.9, 0.15),
      bottomRight: NormPoint(0.85, 0.9),
      bottomLeft: NormPoint(0.12, 0.88),
    );
    final restored = Quad.fromJson(original.toJson());
    expect(restored.topLeft.x, closeTo(0.1, 0.0001));
    expect(restored.bottomRight.y, closeTo(0.9, 0.0001));
  });

  test('moving a corner clamps it inside the image', () {
    final moved = Quad.fullFrame.move(
      CropCorner.topLeft,
      const NormPoint(-0.2, 1.4),
    );
    expect(moved.topLeft.x, 0);
    expect(moved.topLeft.y, 1);
  });
}
