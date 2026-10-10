import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/services/magnet_detector.dart';

void main() {
  group('filtering', () {
    test('a single spike is rejected by the median window', () {
      final detector = MagnetDetector(threshold: 150);

      for (var i = 0; i < 10; i++) {
        expect(detector.addSample(50), isNull);
      }
      expect(detector.filtered, closeTo(50, 0.001));

      expect(detector.addSample(900), isNull);
      expect(detector.filtered, closeTo(50, 0.001));
      expect(detector.detected, isFalse);
    });

    test('a step change is smoothed instead of jumped', () {
      final detector = MagnetDetector(threshold: 150);

      for (var i = 0; i < 6; i++) {
        detector.addSample(50);
      }
      // Median becomes 150 only on the third 150 sample, then the EMA starts
      // gliding from 50 towards 150 with alpha = 0.3.
      detector.addSample(150);
      detector.addSample(150);
      expect(detector.addSample(150), isNull);
      expect(detector.filtered, closeTo(80, 0.5));
      expect(detector.filtered, lessThan(150));
      expect(detector.detected, isFalse);
    });
  });

  group('confirmation', () {
    test('a sustained rise triggers only after confirmSamples', () {
      final detector = MagnetDetector(threshold: 150);

      expect(detector.addSample(200), isNull);
      expect(detector.addSample(200), isNull);
      expect(detector.addSample(200), MagnetEvent.approach);
      expect(detector.detected, isTrue);
    });

    test('a single dip does not undo the detection', () {
      final detector = MagnetDetector(threshold: 150);
      _triggerApproach(detector);

      expect(detector.addSample(50), isNull);
      expect(detector.addSample(50), isNull);
      expect(detector.detected, isTrue);
    });

    test('the removal also needs a sustained drop', () {
      final detector = MagnetDetector(threshold: 150);
      _triggerApproach(detector);

      var samples = 0;
      MagnetEvent? event;
      while (event == null && samples < 50) {
        event = detector.addSample(50);
        samples++;
      }

      expect(event, MagnetEvent.removal);
      expect(samples, greaterThanOrEqualTo(detector.confirmSamples));
      expect(detector.detected, isFalse);
    });

    test('the dead zone between release and threshold keeps the state', () {
      final detector = MagnetDetector(threshold: 150);
      _triggerApproach(detector);

      for (var i = 0; i < 20; i++) {
        expect(detector.addSample(120), isNull);
      }
      expect(detector.detected, isTrue);
    });
  });

  group('threshold', () {
    test('a new threshold applies to the next samples', () {
      final detector = MagnetDetector(threshold: 150);
      _triggerApproach(detector);
      detector.addSample(50);
      while (detector.detected) {
        detector.addSample(50);
      }

      detector.threshold = 300;
      expect(detector.releaseThreshold, closeTo(180, 0.001));
      for (var i = 0; i < 20; i++) {
        expect(detector.addSample(200), isNull);
      }
      expect(detector.detected, isFalse);
    });
  });

  group('cooldown', () {
    test('edges are suppressed until the cooldown elapses', () {
      var now = DateTime(2026, 1, 1);
      final detector = MagnetDetector(
        threshold: 150,
        cooldown: const Duration(seconds: 2),
        clock: () => now,
      );

      expect(_firstEvent(detector, 200), MagnetEvent.approach);
      detector.acknowledgeTrigger();

      expect(_firstEvent(detector, 50), isNull);
      expect(detector.detected, isFalse);

      now = now.add(const Duration(seconds: 3));
      expect(_firstEvent(detector, 200), MagnetEvent.approach);
    });

    test('without an acknowledged trigger there is no cooldown', () {
      final detector = MagnetDetector(threshold: 150);

      expect(_firstEvent(detector, 200), MagnetEvent.approach);
      expect(_firstEvent(detector, 50), MagnetEvent.removal);
      expect(_firstEvent(detector, 200), MagnetEvent.approach);
    });
  });
}

/// Feeds [raw] until an edge comes back, giving up after [max] samples.
MagnetEvent? _firstEvent(MagnetDetector detector, double raw, {int max = 60}) {
  for (var i = 0; i < max; i++) {
    final event = detector.addSample(raw);
    if (event != null) return event;
  }
  return null;
}

void _triggerApproach(MagnetDetector detector) {
  expect(_firstEvent(detector, 200), MagnetEvent.approach);
}
