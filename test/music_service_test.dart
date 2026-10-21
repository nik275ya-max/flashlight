import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/services/music_service.dart';

/// An [AudioPlayer] that never touches the platform.
///
/// Only the members used by [MusicService] are implemented; everything else
/// throws through `noSuchMethod`.
class _FakePlayer implements AudioPlayer {
  final List<String> plays = <String>[];
  final List<double> volumes = <double>[];
  final List<AudioContext> contexts = <AudioContext>[];
  int stops = 0;
  int disposes = 0;
  bool playing = false;

  @override
  PlayerState get state => playing ? PlayerState.playing : PlayerState.stopped;

  @override
  Future<void> setAudioContext(AudioContext ctx) async {
    contexts.add(ctx);
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    final path = (source as DeviceFileSource).path;
    if (path.startsWith('/bad')) {
      throw const FormatException('broken file');
    }
    plays.add(path);
    playing = true;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
  }

  @override
  Future<void> dispose() async {
    disposes++;
    playing = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected call: ${invocation.memberName}');
}

void main() {
  late List<_FakePlayer> created;

  MusicService service() {
    created = <_FakePlayer>[];
    return MusicService(
      playerFactory: () {
        final player = _FakePlayer();
        created.add(player);
        return player;
      },
    );
  }

  test('a new track mixes with the one already playing', () async {
    final music = service();

    await music.play('/a.mp3');
    await music.play('/b.mp3');

    expect(created, hasLength(2));
    // Starting b.mp3 never touched the player of a.mp3.
    expect(created[0].plays, ['/a.mp3']);
    expect(created[0].stops, 0);
    expect(created[1].plays, ['/b.mp3']);
    expect(music.activePaths, {'/a.mp3', '/b.mp3'});
    expect(music.isPlaying, isTrue);
  });

  test('playing the same file again restarts only that track', () async {
    final music = service();

    await music.play('/a.mp3');
    await music.play('/b.mp3');
    await music.play('/a.mp3');

    expect(created, hasLength(2)); // no third player is allocated
    expect(created[0].stops, 1); // a.mp3 was restarted
    expect(created[1].stops, 0); // b.mp3 kept playing untouched
    expect(created[1].plays, ['/b.mp3']);
  });

  test('players start without audio focus so they cannot interrupt', () async {
    final music = service();

    await music.play('/a.mp3');
    await music.play('/b.mp3');

    expect(created, hasLength(2));
    for (final player in created) {
      expect(player.contexts, hasLength(1));
      expect(
        player.contexts.single.android.audioFocus,
        AndroidAudioFocus.none,
      );
    }
  });

  test('a later volume applies to the next track only', () async {
    final music = service();

    await music.setVolume(0.3);
    await music.play('/a.mp3');
    await music.setVolume(0.9);
    await music.play('/b.mp3');

    expect(created[0].volumes, [0.3]);
    expect(created[1].volumes, [0.9]);
    expect(music.volume, 0.9);
  });

  test('stop ends every track of the mix', () async {
    final music = service();
    await music.play('/a.mp3');
    await music.play('/b.mp3');

    await music.stop();

    expect(created[0].stops, greaterThanOrEqualTo(1));
    expect(created[1].stops, greaterThanOrEqualTo(1));
    expect(created.every((player) => player.disposes == 1), isTrue);
    expect(music.activePaths, isEmpty);
    expect(music.isPlaying, isFalse);
  });

  test('a broken file is reported and left out of the mix', () async {
    final music = service();

    await music.play('/bad.mp3');

    expect(music.lastError, isNotNull);
    expect(music.activePaths, isEmpty);
    expect(created.single.disposes, 1);

    // The service stays usable for the next track.
    await music.play('/good.mp3');
    expect(music.lastError, isNull);
    expect(music.activePaths, {'/good.mp3'});
    expect(created, hasLength(2));
  });

  test('volume is clamped into 0.0–1.0', () async {
    final music = service();

    await music.setVolume(1.5);
    await music.play('/a.mp3');

    expect(music.volume, 1.0);
    expect(created.single.volumes, [1.0]);
  });
}
