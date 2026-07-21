import 'package:appflowy/workspace/presentation/home/menu/view/double_click_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoubleClickDetector', () {
    final t0 = DateTime(2026, 1, 1, 12);
    const window = Duration(milliseconds: 300);

    test('a single tap is not a double-click', () {
      final detector = DoubleClickDetector(window: window);
      expect(detector.isDoubleClick(t0), isFalse);
    });

    test('two taps inside the window are a double-click', () {
      final detector = DoubleClickDetector(window: window);
      expect(detector.isDoubleClick(t0), isFalse);
      expect(
        detector.isDoubleClick(t0.add(const Duration(milliseconds: 150))),
        isTrue,
      );
    });

    test('two taps outside the window are two singles', () {
      final detector = DoubleClickDetector(window: window);
      expect(detector.isDoubleClick(t0), isFalse);
      expect(
        detector.isDoubleClick(t0.add(const Duration(milliseconds: 301))),
        isFalse,
      );
    });

    test('a completed double-click resets: a rapid third tap starts fresh',
        () {
      final detector = DoubleClickDetector(window: window);
      expect(detector.isDoubleClick(t0), isFalse);
      expect(
        detector.isDoubleClick(t0.add(const Duration(milliseconds: 100))),
        isTrue,
      );
      // 100ms after the double completed — must NOT chain into another
      // double, or triple-clicks would fire rename twice.
      expect(
        detector.isDoubleClick(t0.add(const Duration(milliseconds: 200))),
        isFalse,
      );
      // ...but a fourth tap right after the third IS a new double.
      expect(
        detector.isDoubleClick(t0.add(const Duration(milliseconds: 300))),
        isTrue,
      );
    });
  });
}
