import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashlight/controllers/app_controller.dart';
import 'package:flashlight/models/script_action.dart';
import 'package:flashlight/services/magnet_service.dart';
import 'package:flashlight/services/torch_service.dart';

class _FakeTorch extends TorchService {
  @override
  Future<bool> setOn(bool on) async => true;
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
}
