import 'package:torch_light/torch_light.dart';

/// Thin wrapper around the platform torch.
///
/// Keeps track of the last known torch state so the rest of the app can read
/// it synchronously.
class TorchService {
  bool _isOn = false;
  bool get isOn => _isOn;

  String? lastError;
  bool _available = false;
  bool get available => _available;

  Future<bool> checkAvailability() async {
    try {
      _available = await TorchLight.isTorchAvailable();
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// Turns the torch on ([on] = true) or off ([on] = false).
  ///
  /// Returns true on success. On failure the internal state is left unchanged
  /// and [lastError] is populated.
  Future<bool> setOn(bool on) async {
    if (on == _isOn) return true;
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      _isOn = on;
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}
