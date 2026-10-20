import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashlight/controllers/app_controller.dart';
import 'package:flashlight/models/script_action.dart';
import 'package:flashlight/services/loudness_service.dart';
import 'package:flashlight/services/magnet_service.dart';
import 'package:flashlight/services/music_service.dart';
import 'package:flashlight/services/torch_service.dart';

class _FakeTorch extends TorchService {
  @override
  Future<bool> setOn(bool on) async => true;
}

class _RecordingTorch extends TorchService {
  final List<bool> calls = <bool>[];

  @override
  Future<bool> setOn(bool on) async {
    calls.add(on);
    return true;
  }
}

class _RecordingMusic extends MusicService {
  final List<double> volumes = <double>[];
  final List<String> plays = <String>[];

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> play(String path) async {
    plays.add(path);
  }
}

/// In-memory LoudnessService: serves pre-seeded values and supports injecting
/// the next analyze() result.
class _FakeLoudness extends LoudnessService {
  _FakeLoudness(Map<String, double> seed)
      : _values = Map<String, double>.from(seed);

  final Map<String, double> _values;
  double? nextResult;

  @override
  double? loudnessOf(String path) => _values[path];

  @override
  Future<double?> analyze(String path, {bool force = false}) async {
    if (!force && _values.containsKey(path)) return _values[path];
    if (nextResult == null) return null;
    _values[path] = nextResult!;
    return nextResult;
  }

  @override
  Future<void> load() async {}
}

Stream<MagnetometerEvent> _sensorStream({
  Duration samplingPeriod = Duration.zero,
}) {
  return Stream<MagnetometerEvent>.empty();
}

AppController _controller(List<int> haptics) {
  return AppController(
    torchService: _FakeTorch(),
    magnetService: MagnetService(streamFactory: _sensorStream),
    hapticFeedback: () {
      haptics.add(haptics.length + 1);
      return Future<void>.value();
    },
  );
}

AppController _controllerWithLoudness(List<int> haptics, LoudnessService loud) {
  return AppController(
    torchService: _FakeTorch(),
    magnetService: MagnetService(streamFactory: _sensorStream),
    loudnessService: loud,
    hapticFeedback: () {
      haptics.add(haptics.length + 1);
      return Future<void>.value();
    },
  );
}

AppController _controllerWithTorch(TorchService torch, List<int> haptics) {
  return AppController(
    torchService: torch,
    magnetService: MagnetService(streamFactory: _sensorStream),
    hapticFeedback: () {
      haptics.add(haptics.length + 1);
      return Future<void>.value();
    },
  );
}

void _replaceScript(AppController controller, ScriptAction action) {
  while (controller.scripts[0].isNotEmpty) {
    controller.removeAction(0, 0);
  }
  controller.addAction(action, scriptIndex: 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('vibrates once when the script starts', () async {
    final haptics = <int>[];
    final controller = _controller(haptics);
    _replaceScript(
      controller,
      const ScriptAction(type: ActionType.delay, delayMs: 50),
    );

    await controller.runScript();

    expect(haptics, [1]);
    controller.dispose();
  });

  test('does not vibrate when the setting is off', () async {
    final haptics = <int>[];
    final controller = _controller(haptics);
    _replaceScript(
      controller,
      const ScriptAction(type: ActionType.delay, delayMs: 50),
    );
    controller.setHapticOnScript(false);

    await controller.runScript();

    expect(haptics, isEmpty);
    controller.dispose();
  });

  test('a new run interrupts the previous one and advances the stage', () async {
    final haptics = <int>[];
    final controller = _controller(haptics);
    _replaceScript(
      controller,
      const ScriptAction(type: ActionType.delay, delayMs: 300),
    );
    controller.addScript();

    final running = controller.runScript();
    expect(controller.stageIndex, 1);

    // Second trigger must interrupt the first run and start stage 2.
    await controller.runScript();
    expect(controller.stageIndex, 2);

    await running;
    expect(controller.scriptRunning, isFalse);
    controller.dispose();
  });

  test('resetCounter rewinds the stage to the first script', () async {
    final haptics = <int>[];
    final controller = _controller(haptics);
    while (controller.scripts[0].isNotEmpty) {
      controller.removeAction(0, 0);
    }
    controller.addAction(
      const ScriptAction(type: ActionType.resetCounter),
      scriptIndex: 0,
    );
    controller.addScript();

    await controller.runScript();
    expect(controller.stageIndex, 0);

    await controller.runScript();
    expect(controller.stageIndex, 0);
    controller.dispose();
  });

  test('stage stops after the last script until manual reset', () async {
    final haptics = <int>[];
    final controller = _controller(haptics);
    _replaceScript(
      controller,
      const ScriptAction(type: ActionType.delay, delayMs: 10),
    );
    controller.addScript();

    await controller.runScript(); // stage 0 -> 1
    await controller.runScript(); // stage 1 -> 2 (blocked)
    expect(controller.stageBlocked, isTrue);
    expect(haptics, hasLength(2));

    await controller.runScript(); // blocked, no haptic
    expect(haptics, hasLength(2));

    controller.resetStageCounter();
    expect(controller.stageIndex, 0);
    await controller.runScript();
    expect(haptics, hasLength(3));
    controller.dispose();
  });

  test('resetCounter can rewind to a later script', () async {
    final controller = _controller(<int>[]);
    _replaceScript(
      controller,
      const ScriptAction(type: ActionType.resetCounter, resetToScriptIndex: 1),
    );
    controller.addScript();
    controller.addScript();

    await controller.runScript();
    expect(controller.stageIndex, 1);
    controller.dispose();
  });

  test('the default haptic path never throws', () async {
    final controller = AppController(
      torchService: _FakeTorch(),
      magnetService: MagnetService(streamFactory: _sensorStream),
    );
    _replaceScript(
      controller,
      const ScriptAction(type: ActionType.delay, delayMs: 50),
    );

    await controller.runScript();

    expect(controller.scriptRunning, isFalse);
    controller.dispose();
  });

  test('the haptic setting survives a restart', () async {
    final first = _controller(<int>[]);
    await first.init();
    expect(first.hapticOnScript, isTrue);

    first.setHapticOnScript(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('hapticOnScript'), isFalse);

    final second = _controller(<int>[]);
    await second.init();
    expect(second.hapticOnScript, isFalse);

    first.dispose();
    second.dispose();
  });

  test('scripts and stageIndex survive a restart', () async {
    final first = _controller(<int>[]);
    await first.init();
    first.addScript();
    first.addAction(
      const ScriptAction(type: ActionType.stopMusic),
      scriptIndex: 0,
    );
    await first.runScript(); // stage 0 -> 1

    final second = _controller(<int>[]);
    await second.init();
    expect(second.scripts.length, 2);
    expect(second.scripts[0].last.type, ActionType.stopMusic);
    expect(second.stageIndex, 1);

    first.dispose();
    second.dispose();
  });

  group('volume normalization', () {
    test('volumeForAction ignores loudness when normalize is off', () async {
      final loudness = _FakeLoudness({'/a.mp3': -10.0});
      final controller = _controllerWithLoudness(<int>[], loudness);
      _replaceScript(
        controller,
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/a.mp3',
          volume: 0.8,
        ),
      );

      expect(controller.volumeForAction(controller.scripts[0].last), 0.8);
      controller.dispose();
    });

    test('volumeForAction returns the per-track volume without a loudness service', () {
      final controller = _controller(<int>[]);
      _replaceScript(
        controller,
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/a.mp3',
          volume: 0.7,
        ),
      );
      controller.setNormalizeVolume(true);

      // No loudness service injected → falls back to the per-track volume.
      expect(controller.volumeForAction(controller.scripts[0].last), 0.7);
      controller.dispose();
    });

    test('normalizes the loud track down to the quietest level', () async {
      // Track A is loud (-10 dBFS), track B is quiet (-22 dBFS).
      final loudness = _FakeLoudness({'/a.mp3': -10.0, '/b.mp3': -22.0});
      final controller = _controllerWithLoudness(<int>[], loudness);
      _replaceScript(
        controller,
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/a.mp3',
          volume: 1.0,
        ),
      );
      controller.addScript();
      controller.addAction(
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/b.mp3',
          volume: 1.0,
        ),
        scriptIndex: 1,
      );
      controller.setNormalizeVolume(true);

      expect(controller.minLoudnessDb, -22.0);
      // Quiet track B plays at full volume.
      final actionB = controller.scripts[1].last;
      expect(controller.volumeForAction(actionB), closeTo(1.0, 1e-6));
      // Loud track A is attenuated: 10^((-22 - -10)/20) = 10^(-0.6) ≈ 0.251.
      final actionA = controller.scripts[0].last;
      expect(controller.volumeForAction(actionA), closeTo(0.2512, 1e-3));
      controller.dispose();
    });

    test('falls back to per-track volume while loudness is unknown', () async {
      final loudness = _FakeLoudness({'/a.mp3': -10.0});
      final controller = _controllerWithLoudness(<int>[], loudness);
      _replaceScript(
        controller,
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/unmeasured.mp3',
          volume: 0.5,
        ),
      );
      controller.setNormalizeVolume(true);

      // /unmeasured.mp3 has no measurement yet → fallback to the per-track volume.
      expect(controller.volumeForAction(controller.scripts[0].last), 0.5);
      controller.dispose();
    });

    test('normalize runner uses the loudness-scaled volume', () async {
      final music = _RecordingMusic();
      final loudness = _FakeLoudness({'/a.mp3': -10.0, '/b.mp3': -22.0});
      final controller = AppController(
        torchService: _FakeTorch(),
        magnetService: MagnetService(streamFactory: _sensorStream),
        musicService: music,
        loudnessService: loudness,
      );
      _replaceScript(
        controller,
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/a.mp3',
          volume: 0.9,
        ),
      );
      controller.addScript();
      controller.addAction(
        const ScriptAction(
          type: ActionType.playMusic,
          filePath: '/b.mp3',
          volume: 0.1,
        ),
        scriptIndex: 1,
      );
      controller.setNormalizeVolume(true);

      await controller.runScript(); // runs script 0 (the loud track A)

      // Individually A is 0.9, but normalized it is attenuated to ~0.251.
      expect(music.volumes.single, closeTo(0.2512, 1e-3));
      controller.dispose();
    });

    test('ensureLoudness caches via the service and notifies', () async {
      final loudness = _FakeLoudness({});
      final controller = _controllerWithLoudness(<int>[], loudness);
      loudness.nextResult = -15.0;

      final ok = await controller.ensureLoudness('/c.mp3');

      expect(ok, isTrue);
      expect(controller.loudnessOf('/c.mp3'), -15.0);
      controller.dispose();
    });

    test('normalize setting survives a restart', () async {
      final first = _controller(<int>[]);
      await first.init();
      first.setNormalizeVolume(true);

      final second = _controller(<int>[]);
      await second.init();
      expect(second.normalizeVolume, isTrue);

      first.dispose();
      second.dispose();
    });
  });

  group('keep screen on', () {
    test('defaults to true and applies on init', () async {
      final calls = <bool>[];
      final controller = AppController(
        torchService: _FakeTorch(),
        magnetService: MagnetService(streamFactory: _sensorStream),
        setKeepScreenOnPlatform: (keepOn) async {
          calls.add(keepOn);
        },
      );
      await controller.init();

      expect(controller.keepScreenOn, isTrue);
      expect(calls, [true]);

      controller.setKeepScreenOn(false);
      expect(calls, [true, false]);

      controller.dispose();
    });

    test('survives a restart', () async {
      final first = AppController(
        torchService: _FakeTorch(),
        magnetService: MagnetService(streamFactory: _sensorStream),
        setKeepScreenOnPlatform: (_) async {},
      );
      await first.init();
      first.setKeepScreenOn(false);

      final second = AppController(
        torchService: _FakeTorch(),
        magnetService: MagnetService(streamFactory: _sensorStream),
        setKeepScreenOnPlatform: (_) async {},
      );
      await second.init();
      expect(second.keepScreenOn, isFalse);

      first.dispose();
      second.dispose();
    });

    test('survives without a platform callback (tests)', () async {
      final controller = _controller(<int>[]);
      await controller.init();
      expect(controller.keepScreenOn, isTrue);
      controller.setKeepScreenOn(false);
      expect(controller.keepScreenOn, isFalse);
      controller.dispose();
    });
  });

  group('manual button lock', () {
    test('lockButton ignores taps until an unlockButton step runs', () async {
      final torch = _RecordingTorch();
      final controller = _controllerWithTorch(torch, <int>[]);
      controller.setTurnOffAfterScript(false);
      _replaceScript(
        controller,
        const ScriptAction(type: ActionType.lockButton),
      );

      await controller.runScript();
      expect(controller.buttonLocked, isTrue);

      // The tap is ignored while locked: the torch is never touched.
      await controller.toggleTorch();
      expect(torch.calls, isEmpty);

      controller.resetStageCounter();
      _replaceScript(
        controller,
        const ScriptAction(type: ActionType.unlockButton),
      );
      await controller.runScript();
      expect(controller.buttonLocked, isFalse);

      // Tapping works again once unlocked.
      await controller.toggleTorch();
      expect(torch.calls, [true]);
      controller.dispose();
    });

    test('script steps still control the torch while the button is locked', () async {
      final torch = _RecordingTorch();
      final controller = _controllerWithTorch(torch, <int>[]);
      controller.setTurnOffAfterScript(false);
      _replaceScript(
        controller,
        const ScriptAction(
          type: ActionType.lockButton,
        ),
      );
      controller.addAction(const ScriptAction(type: ActionType.torchOn));

      await controller.runScript();

      // Only the scripted torchOn reaches the torch, not the button.
      expect(torch.calls, [true]);
      expect(controller.buttonLocked, isTrue);
      controller.dispose();
    });

    test('the lock state survives a restart', () async {
      final first = _controller(<int>[]);
      await first.init();
      first.setButtonLocked(true);

      final second = _controller(<int>[]);
      await second.init();
      expect(second.buttonLocked, isTrue);

      first.dispose();
      second.dispose();
    });
  });
}
