import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/cover_scrubber.dart';

void main() {
  test('slow drag falls back to one step per 22 pixels', () {
    final controller = CoverScrubSpeedController();

    expect(controller.update(delta: 11, timestamp: Duration.zero), isNull);
    expect(
      controller.update(
        delta: 11,
        timestamp: const Duration(milliseconds: 100),
      ),
      1,
    );
  });

  test('fast drag uses the capsule speed multiplier table', () {
    final controller = CoverScrubSpeedController();

    controller.update(delta: 0, timestamp: Duration.zero);
    expect(
      controller.update(
        delta: 200,
        timestamp: const Duration(milliseconds: 100),
      ),
      10,
    );
  });

  test('steps are throttled to one update every 90 milliseconds', () {
    final controller = CoverScrubSpeedController();

    controller.update(delta: 0, timestamp: Duration.zero);
    expect(
      controller.update(
        delta: 60,
        timestamp: const Duration(milliseconds: 100),
      ),
      isNotNull,
    );
    expect(
      controller.update(
        delta: 60,
        timestamp: const Duration(milliseconds: 150),
      ),
      isNull,
    );
  });

  test(
    'distance fallback keeps the accumulated direction after a tiny reversal',
    () {
      final controller = CoverScrubSpeedController();

      controller.update(delta: 0, timestamp: Duration.zero);
      controller.update(
        delta: 60,
        timestamp: const Duration(milliseconds: 100),
      );
      expect(
        controller.update(
          delta: 60,
          timestamp: const Duration(milliseconds: 150),
        ),
        isNull,
      );
      expect(
        controller.update(
          delta: -1,
          timestamp: const Duration(milliseconds: 200),
        ),
        2,
      );
    },
  );

  test('reset clears accumulated distance and timing', () {
    final controller = CoverScrubSpeedController();

    controller.update(delta: 20, timestamp: Duration.zero);
    controller.reset();
    expect(
      controller.update(delta: 2, timestamp: const Duration(milliseconds: 10)),
      isNull,
    );
  });
}
