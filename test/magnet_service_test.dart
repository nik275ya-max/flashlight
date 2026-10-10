import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/services/magnet_service.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test('a stream error is retried until the sensor answers again', () async {
    final sensor = StreamController<MagnetometerEvent>.broadcast();
    var calls = 0;

    Stream<MagnetometerEvent> factory({
      Duration samplingPeriod = Duration.zero,
    }) {
      calls++;
      if (calls == 1) {
        return Stream<MagnetometerEvent>.error(StateError('nope'));
      }
      return sensor.stream;
    }

    final service = MagnetService(
      streamFactory: factory,
      retryDelay: const Duration(milliseconds: 200),
      maxRetryDelay: const Duration(milliseconds: 400),
    );
    final statuses = <MagnetStatus>[];
    service.onUpdate = () => statuses.add(service.status);

    final readings = <MagneticReading>[];
    final subscription = service.readings.listen(readings.add);

    service.start();
    expect(service.status, MagnetStatus.listening);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.status, MagnetStatus.reconnecting);
    expect(calls, 1);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(service.status, MagnetStatus.listening);
    expect(calls, 2);
    expect(
      statuses,
      containsAllInOrder([
        MagnetStatus.listening,
        MagnetStatus.reconnecting,
        MagnetStatus.listening,
      ]),
    );

    sensor.add(MagnetometerEvent(3, 4, 0, DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(readings, hasLength(1));
    expect(readings.single.magnitude, closeTo(5, 0.001));

    await subscription.cancel();
    await sensor.close();
    await service.dispose();
  });

  test('dispose stops the pending retries', () async {
    var calls = 0;

    Stream<MagnetometerEvent> factory({
      Duration samplingPeriod = Duration.zero,
    }) {
      calls++;
      return Stream<MagnetometerEvent>.error(StateError('nope'));
    }

    final service = MagnetService(
      streamFactory: factory,
      retryDelay: const Duration(milliseconds: 50),
    );

    service.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await service.dispose();
    final callsAtDispose = calls;

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(calls, callsAtDispose);
  });
}
