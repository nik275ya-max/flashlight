import 'package:flutter/foundation.dart';

import '../models/script_action.dart';
import 'music_service.dart';
import 'torch_service.dart';

/// Executes a list of [ScriptAction]s one after another.
///
/// Only one run can happen at a time. A run can be cancelled between steps,
/// and long delays are split into small ticks so cancellation stays
/// responsive. [cancel] also stops any music that is still playing.
class ScriptRunner {
  ScriptRunner(this._torch, {MusicService? music})
    : _music = music ?? MusicService();

  final TorchService _torch;
  final MusicService _music;

  bool _running = false;
  bool get isRunning => _running;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  bool _cancelRequested = false;

  Future<void>? _activeRun;

  /// Completes when the current (or last) run finishes, including cancellation.
  Future<void> get activeRun => _activeRun ?? Future<void>.value();

  /// Called whenever the running state or the active step changes.
  VoidCallback? onUpdate;

  /// Called once when an [ActionType.resetCounter] step executes.
  ValueChanged<int>? onCounterReset;

  MusicService get music => _music;

  /// Resolves the effective playback volume for a [ActionType.playMusic] step.
  /// The controller plugs a normalizer here so a global override can ignore
  /// per-track volumes and play everything at the quietest track's level.
  double Function(ScriptAction)? volumeFor;

  Future<void> run(
    List<ScriptAction> actions, {
    bool turnOffAtEnd = true,
  }) async {
    if (_running || actions.isEmpty) return;

    _running = true;
    _cancelRequested = false;
    _notify();

    final future = _execute(actions, turnOffAtEnd: turnOffAtEnd);
    _activeRun = future;
    await future;
    if (identical(_activeRun, future)) {
      _activeRun = null;
    }
  }

  Future<void> _execute(
    List<ScriptAction> actions, {
    required bool turnOffAtEnd,
  }) async {
    for (var i = 0; i < actions.length; i++) {
      if (_cancelRequested) break;
      _currentIndex = i;
      _notify();

      final action = actions[i];
      switch (action.type) {
        case ActionType.torchOn:
          await _torch.setOn(true);
          break;
        case ActionType.torchOff:
          await _torch.setOn(false);
          break;
        case ActionType.delay:
          await _torch.setOn(action.lightOn);
          await _wait(action.delayMs);
          break;
        case ActionType.playMusic:
          final path = action.filePath;
          if (path != null && path.isNotEmpty) {
            final v = volumeFor?.call(action) ?? action.effectiveVolume;
            await _music.setVolume(v);
            await _music.play(path);
          }
          break;
        case ActionType.stopMusic:
          await _music.stop();
          break;
        case ActionType.resetCounter:
          onCounterReset?.call(action.resetToScriptIndex);
          break;
      }
    }

    if (_cancelRequested) {
      await _music.stop();
    } else if (turnOffAtEnd) {
      await _torch.setOn(false);
    }

    _running = false;
    _currentIndex = -1;
    _cancelRequested = false;
    _notify();
  }

  void cancel() {
    if (_running) _cancelRequested = true;
  }

  Future<void> _wait(int milliseconds) async {
    const tick = 40;
    var remaining = milliseconds;
    while (remaining > 0 && !_cancelRequested) {
      final step = remaining < tick ? remaining : tick;
      await Future<void>.delayed(Duration(milliseconds: step));
      remaining -= step;
    }
  }

  void _notify() => onUpdate?.call();
}
