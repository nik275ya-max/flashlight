/// A confirmed edge produced by [MagnetDetector].
enum MagnetEvent {
  /// The field grew past the threshold and stayed there.
  approach,

  /// The field fell back below the release threshold and stayed there.
  removal,
}

/// Turns noisy raw magnetometer magnitudes into confirmed trigger events.
///
/// Raw magnetometer samples are jittery: a single spike must not start the
/// script and a single dip must not end the detection. The detector therefore
/// chains three guards:
///
/// 1. a median window that rejects isolated outliers,
/// 2. an exponential moving average that smooths the remaining noise,
/// 3. a run-length confirmation, so a state change only counts once the
///    filtered value stayed on the new side of the threshold for
///    [confirmSamples] samples in a row.
///
/// After an event is acknowledged with [acknowledgeTrigger] further edges are
/// suppressed for [cooldown], so one magnet pass cannot start the script twice.
class MagnetDetector {
  MagnetDetector({
    required this.threshold,
    this.releaseFactor = 0.6,
    this.windowSize = 5,
    this.smoothing = 0.3,
    this.confirmSamples = 3,
    this.cooldown = const Duration(seconds: 2),
    this.clock = DateTime.now,
  }) {
    assert(windowSize > 0 && windowSize.isOdd, 'windowSize must be odd');
    assert(confirmSamples > 0);
    assert(smoothing > 0 && smoothing <= 1);
    assert(releaseFactor > 0 && releaseFactor < 1);
  }

  /// Field magnitude in µT at which the magnet counts as approaching.
  double threshold;

  /// Fraction of [threshold] below which the magnet counts as removed again.
  final double releaseFactor;

  /// Number of raw samples kept for the median filter. Must be odd.
  final int windowSize;

  /// Exponential moving average factor, 0 < smoothing <= 1.
  final double smoothing;

  /// How many consecutive filtered samples are needed to accept a change.
  final int confirmSamples;

  /// How long edges stay suppressed after an acknowledged trigger.
  final Duration cooldown;

  /// Clock used for the cooldown, injectable in tests.
  final DateTime Function() clock;

  final List<double> _window = <double>[];

  double _filtered = 0;
  bool _hasFiltered = false;
  bool _detected = false;
  int _aboveRun = 0;
  int _belowRun = 0;
  DateTime? _lastTrigger;

  /// The most recent filtered magnitude in µT.
  double get filtered => _filtered;

  /// Whether the magnet is currently considered present.
  bool get detected => _detected;

  /// Value below which the magnet counts as removed again.
  double get releaseThreshold => threshold * releaseFactor;

  /// Feeds one raw magnitude and returns the resulting edge, if any.
  ///
  /// Returns null for noise, for a state change that is not confirmed yet and
  /// for edges suppressed by the cooldown.
  MagnetEvent? addSample(double raw) {
    _filtered = _smooth(raw);

    MagnetEvent? edge;
    if (!_detected) {
      if (_filtered >= threshold) {
        _aboveRun++;
        _belowRun = 0;
        if (_aboveRun >= confirmSamples) {
          _detected = true;
          _aboveRun = 0;
          edge = MagnetEvent.approach;
        }
      } else {
        _aboveRun = 0;
      }
    } else {
      if (_filtered <= releaseThreshold) {
        _belowRun++;
        _aboveRun = 0;
        if (_belowRun >= confirmSamples) {
          _detected = false;
          _belowRun = 0;
          edge = MagnetEvent.removal;
        }
      } else {
        _belowRun = 0;
      }
    }

    if (edge == null) return null;
    final lastTrigger = _lastTrigger;
    if (lastTrigger != null && clock().difference(lastTrigger) < cooldown) {
      return null;
    }
    return edge;
  }

  /// Starts the cooldown window because the caller acted on an edge.
  void acknowledgeTrigger() => _lastTrigger = clock();

  double _smooth(double raw) {
    _window.add(raw);
    if (_window.length > windowSize) _window.removeAt(0);

    final sorted = [..._window]..sort();
    final median = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;

    if (!_hasFiltered) {
      _hasFiltered = true;
      return median;
    }
    return _filtered + smoothing * (median - _filtered);
  }
}
