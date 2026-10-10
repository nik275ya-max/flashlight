import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/services/haptic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buzzes the vibrator for the short duration when it exists', () async {
    final durations = <int>[];
    final service = HapticService(
      hasVibrator: () async => true,
      vibrate: (milliseconds) async => durations.add(milliseconds),
    );

    await service.buzz();

    expect(durations, [HapticService.buzzMilliseconds]);
  });

  test('falls back to the platform haptic without a vibrator', () async {
    final service = HapticService(
      hasVibrator: () async => false,
      vibrate: (milliseconds) async => fail('vibrator must not be used'),
    );

    await expectLater(service.buzz(), completes);
  });

  test('falls back when the vibrator call fails', () async {
    final service = HapticService(
      hasVibrator: () async => true,
      vibrate: (milliseconds) async => throw StateError('busy'),
    );

    await expectLater(service.buzz(), completes);
  });

  test('swallows a failing vibrator probe', () async {
    final service = HapticService(
      hasVibrator: () async => throw StateError('no probe'),
      vibrate: (milliseconds) async => fail('vibrator must not be used'),
    );

    await expectLater(service.buzz(), completes);
  });
}
