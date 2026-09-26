import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

void main() {
  test('opencv_dart smoke test', () {
    final mat = cv.Mat.zeros(100, 100, cv.MatType.CV_8UC3);
    expect(mat.rows, 100);
    expect(mat.cols, 100);
    final gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    expect(gray.channels, 1);
    mat.dispose();
    gray.dispose();
  });
}
