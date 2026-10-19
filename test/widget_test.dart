import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/models/script_action.dart';
import 'package:flashlight/services/script_runner.dart';
import 'package:flashlight/services/torch_service.dart';

class _FakeTorch extends TorchService {
  final List<bool> calls = <bool>[];

  @override
  Future<bool> setOn(bool on) async {
    calls.add(on);
    return true;
  }
}

void main() {
  group('ScriptAction', () {
    test('serialises and restores every action type', () {
      const actions = [
        ScriptAction(type: ActionType.torchOn),
        ScriptAction(type: ActionType.torchOff),
        ScriptAction(type: ActionType.delay, delayMs: 1500, lightOn: true),
        ScriptAction(type: ActionType.resetCounter, resetToScriptIndex: 2),
      ];

      final restored = actions
          .map((action) => ScriptAction.fromJson(action.toJson()))
          .toList();

      for (var i = 0; i < actions.length; i++) {
        expect(restored[i].type, actions[i].type);
        expect(restored[i].delayMs, actions[i].delayMs);
        expect(restored[i].lightOn, actions[i].lightOn);
        expect(restored[i].resetToScriptIndex, actions[i].resetToScriptIndex);
      }
    });

    test('falls back to a delay for unknown action types', () {
      final action = ScriptAction.fromJson(const {
        'type': 'nope',
        'delayMs': 250,
      });
      expect(action.type, ActionType.delay);
      expect(action.delayMs, 250);
    });

    test('serialises and restores playMusic volume', () {
      const action = ScriptAction(
        type: ActionType.playMusic,
        filePath: '/a.mp3',
        volume: 0.35,
      );
      final restored = ScriptAction.fromJson(action.toJson());
      expect(restored.type, ActionType.playMusic);
      expect(restored.filePath, '/a.mp3');
      expect(restored.volume, 0.35);
    });

    test('playMusic volume defaults to full when absent in json', () {
      final restored = ScriptAction.fromJson(const {
        'type': 'playMusic',
        'filePath': '/a.mp3',
      });
      expect(restored.volume, 1.0);
    });

    test('describes a delay with the light state', () {
      const action = ScriptAction(type: ActionType.delay, delayMs: 1500);
      expect(action.title, contains('Задержка'));
      expect(action.title, contains('свет выкл'));
      expect(
        const ScriptAction(
          type: ActionType.delay,
          delayMs: 2000,
          lightOn: true,
        ).title,
        contains('свет вкл'),
      );
    });
  });

  group('ScriptRunner', () {
    test('runs torch actions and delays in order, then turns off', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final torch = _FakeTorch();
      final runner = ScriptRunner(torch);

      await runner.run(const [
        ScriptAction(type: ActionType.torchOn),
        ScriptAction(type: ActionType.delay, delayMs: 40, lightOn: true),
        ScriptAction(type: ActionType.torchOff),
      ], turnOffAtEnd: true);

      expect(torch.calls, [true, true, false, false]);
      expect(runner.isRunning, isFalse);
      expect(runner.currentIndex, -1);
    });

    test('keeps the torch on when turnOffAtEnd is false', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final torch = _FakeTorch();
      final runner = ScriptRunner(torch);

      await runner.run(const [
        ScriptAction(type: ActionType.torchOn),
      ], turnOffAtEnd: false);

      expect(torch.calls, [true]);
    });

    test('a second run is ignored while the first is active', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final torch = _FakeTorch();
      final runner = ScriptRunner(torch);

      final first = runner.run(const [
        ScriptAction(type: ActionType.delay, delayMs: 200),
      ]);
      final second = runner.run(const [ScriptAction(type: ActionType.torchOn)]);

      await Future.wait([first, second]);

      expect(torch.calls, isNot(contains(true)));
      expect(runner.isRunning, isFalse);
    });

    test('cancel stops the script early', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final torch = _FakeTorch();
      final runner = ScriptRunner(torch);

      final run = runner.run(const [
        ScriptAction(type: ActionType.delay, delayMs: 3000),
        ScriptAction(type: ActionType.torchOn),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      runner.cancel();
      await run;

      expect(torch.calls, isNot(contains(true)));
      expect(runner.isRunning, isFalse);
    });
  });
}
