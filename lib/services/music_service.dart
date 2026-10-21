import 'package:audioplayers/audioplayers.dart';

/// Signature of the [AudioPlayer] factory, injectable in tests.
typedef AudioPlayerFactory = AudioPlayer Function();

/// Plays local audio files and mixes them together.
///
/// A single [AudioPlayer] can hold only one source, so every track gets its
/// own player: starting a new file never interrupts the tracks that are
/// already playing, the platform simply mixes the streams into one output.
///
/// Playback is never stopped implicitly - neither at the end of a script nor
/// when a run is cancelled. Only an explicit [ActionType.stopMusic] step,
/// [stop] or [dispose] ends it. Playing the same file again restarts just that
/// track and leaves the rest of the mix alone.
///
/// Every failure is captured in [lastError] and never thrown, so a missing
/// file cannot crash the script runner.
class MusicService {
  MusicService({AudioPlayerFactory? playerFactory})
    : _newPlayer = playerFactory ?? AudioPlayer.new;

  /// The audio context every new player is started with.
  ///
  /// A single [AudioPlayer] holds one source, so the mix needs several
  /// players. With the default [AndroidAudioFocus.gain] the second player
  /// takes the audio focus away from the first one: Android hands the previous
  /// holder an `AUDIOFOCUS_LOSS`, and audioplayers reacts by pausing it - the
  /// new track would interrupt the running one instead of mixing with it.
  /// Turning the focus handling off makes every player simply play alongside
  /// the others.
  static final AudioContext mixContext = AudioContext(
    android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
  );

  final AudioPlayerFactory _newPlayer;

  /// One live player per file path.
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};

  String? lastError;

  /// Volume applied to the next [play], 0.0–1.0.
  double _volume = 1.0;
  double get volume => _volume;

  /// Files that currently have a player, i.e. everything [stop] will end.
  Set<String> get activePaths => Set<String>.unmodifiable(_players.keys);

  /// True while at least one track of the mix is playing.
  bool get isPlaying => _players.values.any(
    (player) => player.state == PlayerState.playing,
  );

  /// Stores [volume] (clamped to 0.0–1.0) for the next [play]. Tracks that are
  /// already running keep the level they were started with, so a running mix
  /// is never re-balanced by a later step.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
  }

  Future<void> play(String path) async {
    final existing = _players[path];
    final player = existing ?? _newPlayer();
    if (existing == null) _players[path] = player;

    try {
      if (existing == null) {
        // Release the audio focus handling so starting this track cannot pause
        // the ones that are already playing (see [mixContext]).
        await player.setAudioContext(mixContext);
      } else {
        // The same file again: restart only this track, the mix keeps playing.
        await player.stop();
      }
      await player.setVolume(_volume);
      await player.play(DeviceFileSource(path));
      lastError = null;
    } on Exception catch (e) {
      lastError = e.toString();
      // A failed first play leaves nothing behind worth keeping.
      if (existing == null) {
        _players.remove(path);
        try {
          await player.dispose();
        } on Exception catch (_) {
          // Disposal failures must not mask the original error.
        }
      }
    }
  }

  /// Stops and releases every track of the mix.
  ///
  /// This is the only way playback ends besides an explicit stopMusic step and
  /// [dispose].
  Future<void> stop() async {
    final players = List<AudioPlayer>.of(_players.values);
    _players.clear();
    for (final player in players) {
      try {
        await player.stop();
      } on Exception catch (_) {
        // The remaining tracks must still be released.
      }
      try {
        await player.dispose();
      } on Exception catch (_) {
        // Ignore: nothing else to try.
      }
    }
  }

  Future<void> dispose() => stop();
}
