import 'package:audioplayers/audioplayers.dart';

/// Plays a single local audio file; a new [play] replaces whatever was
/// playing before. All failures are captured in [lastError] and never
/// throw, so a missing file cannot crash the script runner.
///
/// The underlying [AudioPlayer] is created lazily on the first [play] so
/// unit tests that never touch audio do not need platform channels.
class MusicService {
  MusicService({AudioPlayer? player}) : _injectedPlayer = player;

  final AudioPlayer? _injectedPlayer;
  AudioPlayer? _player;

  String? lastError;
  String? _currentPath;

  /// Volume applied on the next [play] and live via [setVolume], 0.0–1.0.
  double _volume = 1.0;
  double get volume => _volume;

  String? get currentPath => _currentPath;
  bool get isPlaying => _player?.state == PlayerState.playing;

  /// Stores [volume] (clamped to 0.0–1.0) and pushes it to the player when one
  /// exists. Safe to call before [play]; the value sticks across plays.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final player = _player;
    if (player == null) return;
    try {
      await player.setVolume(_volume);
    } on Exception catch (_) {
      // A failed volume call must not break playback.
    }
  }

  Future<void> play(String path) async {
    try {
      final player = _player ??= _injectedPlayer ?? AudioPlayer();
      await player.stop();
      await player.setVolume(_volume);
      await player.play(DeviceFileSource(path));
      _currentPath = path;
      lastError = null;
    } on Exception catch (e) {
      lastError = e.toString();
      _currentPath = null;
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } on Exception catch (_) {
      // Ignore stop failures.
    }
    _currentPath = null;
  }

  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } on Exception catch (_) {
      // Ignore dispose failures.
    }
    _player = null;
  }
}
