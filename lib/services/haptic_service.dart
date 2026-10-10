import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Produces the short buzz that marks the start of a script.
///
/// The primary path is the vibrator API ([Vibration.vibrate]): the platform
/// haptic used by [HapticFeedback.vibrate] goes through
/// `View.performHapticFeedback`, which is silently ignored when the system
/// "touch feedback" setting is off.
///
/// Every failure is swallowed - a missing vibrator, a refused plugin call or
/// a broken platform channel must never break the script that triggered the
/// buzz. When the vibrator cannot be used, the platform haptic is the
/// fallback.
class HapticService {
  HapticService({
    Future<bool> Function()? hasVibrator,
    Future<void> Function(int milliseconds)? vibrate,
  }) : _hasVibrator = hasVibrator ?? Vibration.hasVibrator,
       _vibrate = vibrate ?? ((int ms) => Vibration.vibrate(duration: ms));

  /// Length of the short buzz.
  static const buzzMilliseconds = 60;

  final Future<bool> Function() _hasVibrator;
  final Future<void> Function(int milliseconds) _vibrate;

  Future<void> buzz() async {
    try {
      if (await _hasVibrator()) {
        await _vibrate(buzzMilliseconds);
        return;
      }
    } catch (_) {
      // fall through to the platform haptic
    }

    try {
      await HapticFeedback.vibrate();
    } catch (_) {
      // nothing else to try
    }
  }
}
