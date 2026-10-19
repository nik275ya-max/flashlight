import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/models/script_action.dart';
import 'package:flashlight/services/music_service.dart';
import 'package:flashlight/services/script_runner.dart';
import 'package:flashlight/services/torch_service.dart';

class _FakeTorch extends TorchService {
  final List<bool> calls = [];

  @override
  Future<bool> setOn(bool on) async {
    calls.add(on);
    return true;
  }
}

class _FakeMusic extends MusicService {
  final List<String> plays = [];
  final List<double> volumes = [];
  int stops = 0;

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> play(String path) async {
    plays.add(path);
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playMusic forwards the path to the music service', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music);

    await runner.run(const [
      ScriptAction(type: ActionType.playMusic, filePath: '/tmp/a.mp3'),
    ]);

    expect(music.plays, ['/tmp/a.mp3']);
  });

  test('stopMusic stops the music service', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music);

    await runner.run(const [ScriptAction(type: ActionType.stopMusic)]);

    expect(music.stops, greaterThanOrEqualTo(1));
  });

  test('resetCounter fires the onCounterReset callback', () async {
    final resets = <int>[];
    final runner = ScriptRunner(_FakeTorch(), music: _FakeMusic())
      ..onCounterReset = resets.add;

    await runner.run(const [
      ScriptAction(type: ActionType.resetCounter, resetToScriptIndex: 2),
    ]);

    expect(resets, [2]);
  });

  test('cancel stops music and exposes activeRun', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music);

    final run = runner.run(const [
      ScriptAction(type: ActionType.playMusic, filePath: '/tmp/a.mp3'),
      ScriptAction(type: ActionType.delay, delayMs: 500),
    ]);
    expect(runner.isRunning, isTrue);

    runner.cancel();
    await runner.activeRun;
    await run;

    expect(runner.isRunning, isFalse);
    expect(music.stops, greaterThanOrEqualTo(1));
  });

  test('turnOffAtEnd turns the torch off', () async {
    final torch = _FakeTorch();
    final runner = ScriptRunner(torch, music: _FakeMusic());

    await runner.run(const [ScriptAction(type: ActionType.torchOn)]);

    expect(torch.calls, [true, false]);
  });

  test('playMusic without a path is a no-op', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music);

    await runner.run(const [ScriptAction(type: ActionType.playMusic)]);

    expect(music.plays, isEmpty);
  });

  test('playMusic sets the track volume before playing', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music);

    await runner.run(const [
      ScriptAction(
        type: ActionType.playMusic,
        filePath: '/tmp/a.mp3',
        volume: 0.5,
      ),
    ]);

    expect(music.volumes, [0.5]);
    expect(music.plays, ['/tmp/a.mp3']);
  });

  test('volumeFor resolver overrides the per-track volume', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music)
      ..volumeFor = (_) => 0.3;

    await runner.run(const [
      ScriptAction(
        type: ActionType.playMusic,
        filePath: '/tmp/a.mp3',
        volume: 0.9,
      ),
    ]);

    expect(music.volumes, [0.3]);
  });

  test('volume is clamped into 0.0–1.0', () async {
    final music = _FakeMusic();
    final runner = ScriptRunner(_FakeTorch(), music: music);

    await runner.run(const [
      ScriptAction(
        type: ActionType.playMusic,
        filePath: '/tmp/a.mp3',
        volume: 1.5,
      ),
    ]);

    expect(music.volumes, [1.0]);
  });
}
