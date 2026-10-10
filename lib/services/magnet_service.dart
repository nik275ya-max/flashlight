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

/// Health of the magnetometer subscription.
enum MagnetStatus {
  /// Not started yet or stopped on purpose.
  idle,

  /// Samples are flowing.
  listening,

  /// The sensor stream failed and a resubscription is pending.
  reconnecting,
}

/// Signature of the sensors_plus entry point, injectable for tests.
typedef MagnetometerStreamFactory = Stream<MagnetometerEvent> Function({
  Duration samplingPeriod,
});

/// Streams magnetometer samples from the built-in sensor.
///
/// A stream error (missing sensor, EventChannel failure, Android sensor
/// hiccup) does not kill this service: the subscription is rebuilt after a
/// backoff delay and [status] reports what is going on.
class MagnetService {
  MagnetService({
    MagnetometerStreamFactory? streamFactory,
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 10),
  }) : _streamFactory = streamFactory ?? magnetometerEventStream;

  /// Android does not guarantee the requested rate, but 50 ms gives the
  /// detector enough samples for confirmation without a hot loop.
  static const defaultSamplingPeriod = Duration(milliseconds: 50);

  final MagnetometerStreamFactory _streamFactory;
  final Duration retryDelay;
  final Duration maxRetryDelay;

  final StreamController<MagneticReading> _controller =
      StreamController<MagneticReading>.broadcast();
  StreamSubscription<MagnetometerEvent>? _subscription;
  Timer? _retryTimer;
  Duration _samplingPeriod = defaultSamplingPeriod;
  int _failures = 0;
  bool _disposed = false;
  MagnetStatus _status = MagnetStatus.idle;

  /// Called whenever [status] changes.
  void Function()? onUpdate;

  Stream<MagneticReading> get readings => _controller.stream;

  MagnetStatus get status => _status;
  bool get isListening => _status == MagnetStatus.listening;

  void start({Duration samplingPeriod = defaultSamplingPeriod}) {
    if (_disposed || _subscription != null || _retryTimer != null) return;
    _samplingPeriod = samplingPeriod;
    _subscribe();
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _controller.close();
  }

  void _subscribe() {
    _retryTimer = null;

    late final StreamSubscription<MagnetometerEvent> subscription;
    subscription = _streamFactory(samplingPeriod: _samplingPeriod).listen(
      _onEvent,
      onError: (Object error) {
        if (_disposed || _subscription != subscription) return;
        _subscription = null;
        unawaited(subscription.cancel());
        _failures++;
        _setStatus(MagnetStatus.reconnecting);
        _retryTimer = Timer(_delayFor(_failures), () {
          if (!_disposed) _subscribe();
        });
      },
    );

    _subscription = subscription;
    _setStatus(MagnetStatus.listening);
  }

  void _onEvent(MagnetometerEvent event) {
    if (_disposed || _controller.isClosed) return;
    _failures = 0;
    _setStatus(MagnetStatus.listening);
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
  }

  Duration _delayFor(int failures) {
    final exponent = (failures - 1).clamp(0, 5);
    final milliseconds = (retryDelay.inMilliseconds << exponent).clamp(
      0,
      maxRetryDelay.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds);
  }

  void _setStatus(MagnetStatus next) {
    if (_status == next) return;
    _status = next;
    onUpdate?.call();
  }
}
