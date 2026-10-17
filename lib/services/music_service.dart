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

  String? get currentPath => _currentPath;
  bool get isPlaying => _player?.state == PlayerState.playing;

  Future<void> play(String path) async {
    try {
      final player = _player ??= _injectedPlayer ?? AudioPlayer();
      await player.stop();
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
