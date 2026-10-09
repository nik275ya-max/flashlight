import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// A single magnetometer sample with the pre-computed field magnitude.
class MagneticReading {
  const MagneticReading({
    required this.x,
    required this.y,
    required this.z,
    required this.magnitude,
  });

  final double x;
  final double y;
  final double z;

  /// Length of the (x, y, z) vector in microteslas (µT).
  final double magnitude;
}

/// Streams magnetometer samples from the built-in sensor.
class MagnetService {
  final StreamController<MagneticReading> _controller =
      StreamController<MagneticReading>.broadcast();
  StreamSubscription<MagnetometerEvent>? _subscription;

  Stream<MagneticReading> get readings => _controller.stream;

  bool get isListening => _subscription != null;

  void start({Duration samplingPeriod = const Duration(milliseconds: 100)}) {
    if (_subscription != null) return;
    _subscription = magnetometerEventStream(samplingPeriod: samplingPeriod)
        .listen(
          (event) {
            if (_controller.isClosed) return;
            _controller.add(
              MagneticReading(
                x: event.x,
                y: event.y,
                z: event.z,
                magnitude: math.sqrt(
                  event.x * event.x + event.y * event.y + event.z * event.z,
                ),
              ),
            );
          },
          onError: (Object error) {
            if (!_controller.isClosed) _controller.addError(error);
          },
        );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
