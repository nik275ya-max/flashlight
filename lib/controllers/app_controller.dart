import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/script_action.dart';
import '../services/haptic_service.dart';
import '../services/loudness_service.dart';
import '../services/magnet_detector.dart';
import '../services/magnet_service.dart';
import '../services/music_service.dart';
import '../services/script_runner.dart';
import '../services/torch_service.dart';

/// When the magnet trigger should fire the script.
enum TriggerMode {
  /// Fire as soon as the magnet gets close enough.
  onApproach,

  /// Fire when the magnet is taken away again.
  onRemoval,
}

extension TriggerModeLabel on TriggerMode {
  String get label {
    switch (this) {
      case TriggerMode.onApproach:
        return 'При поднесении магнита';
      case TriggerMode.onRemoval:
        return 'При отдалении магнита';
    }
  }
}

/// Central application state: the list of stage scripts, the detection
/// settings and the live magnetometer values.
class AppController extends ChangeNotifier {
  AppController({
    required TorchService torchService,
    required MagnetService magnetService,
    Future<void> Function()? hapticFeedback,
    MusicService? musicService,
    LoudnessService? loudnessService,
    Future<void> Function(bool keepOn)? setKeepScreenOnPlatform,
  }) : _torch = torchService,
       _magnet = magnetService,
       _music = musicService ?? MusicService(),
       _loudness = loudnessService,
       _hapticFeedback = hapticFeedback ?? HapticService().buzz,
       // ignore: prefer_initializing_formals - keep the public param name
       _setKeepScreenOnPlatform = setKeepScreenOnPlatform {
    _runner = ScriptRunner(_torch, music: _music);
    _runner.onUpdate = notifyListeners;
    _runner.onCounterReset = _onCounterReset;
    _detector = MagnetDetector(threshold: _threshold);
  }

  final TorchService _torch;
  final MagnetService _magnet;
  final MusicService _music;
  final LoudnessService? _loudness;
  final Future<void> Function() _hapticFeedback;
  final Future<void> Function(bool)? _setKeepScreenOnPlatform;
  late final ScriptRunner _runner;
  late final MagnetDetector _detector;

  StreamSubscription<MagneticReading>? _magnetSubscription;
  SharedPreferences? _prefs;
  bool _initialized = false;

  static const _scriptsKey = 'scripts';
  static const _stageIndexKey = 'stageIndex';
  static const _thresholdKey = 'threshold';
  static const _detectionKey = 'detectionEnabled';
  static const _triggerModeKey = 'triggerMode';
  static const _turnOffKey = 'turnOffAfterScript';
  static const _scriptKey = 'script'; // legacy
  static const _hapticKey = 'hapticOnScript';
  static const _normalizeVolumeKey = 'normalizeVolume';
  static const _keepScreenOnKey = 'keepScreenOn';

  // ---------------------------------------------------------------- settings

  List<List<ScriptAction>> _scripts = [defaultScript()];
  List<List<ScriptAction>> get scripts => List.unmodifiable(_scripts);

  int _stageIndex = 0;

  /// Which script will run on the next magnet trigger.
  int get stageIndex => _stageIndex;

  /// True once the stage counter has passed the last script.
  bool get stageBlocked => _stageIndex >= _scripts.length;

  /// Human readable label, e.g. «Стадия 2/3» or «Скрипты завершены».
  String get stageLabel {
    if (stageBlocked) return 'Скрипты завершены — сбросьте счётчик';
    return 'Стадия ${_stageIndex + 1}/${_scripts.length}';
  }

  List<ScriptAction> get activeScript {
    if (stageBlocked || _scripts.isEmpty) return const [];
    return List.unmodifiable(_scripts[_stageIndex]);
  }

  bool _detectionEnabled = true;
  bool get detectionEnabled => _detectionEnabled;

  double _threshold = 150;
  double get threshold => _threshold;

  TriggerMode _triggerMode = TriggerMode.onApproach;
  TriggerMode get triggerMode => _triggerMode;

  bool _turnOffAfterScript = true;
  bool get turnOffAfterScript => _turnOffAfterScript;

  bool _hapticOnScript = true;
  bool get hapticOnScript => _hapticOnScript;

  /// When true every track plays at a waveform-derived volume so the perceived
  /// loudness matches the quietest track. Individual [ScriptAction.volume]
  /// settings are ignored. Falls back to per-track volume on platforms without
  /// loudness analysis or while no measurement is available.
  bool _normalizeVolume = false;
  bool get normalizeVolume => _normalizeVolume;

  /// The minimum RMS (dBFS) across every analyzed playMusic track. The
  /// quietest track drives the shared target loudness. Returns null when no
  /// track has been measured yet.
  double? get minLoudnessDb {
    final loudness = _loudness;
    if (loudness == null) return null;
    double? min;
    for (final action in _scripts.expand((s) => s)) {
      if (action.type != ActionType.playMusic) continue;
      final db = loudness.loudnessOf(action.filePath ?? '');
      if (db == null) continue;
      if (min == null || db < min) min = db;
    }
    return min;
  }

  /// Effective playback volume for [action] under the current normalize state.
  ///
  /// When normalization is on and a loudness measurement exists for the
  /// track, scales the track so its perceived loudness matches [minLoudnessDb]
  /// (quietest plays at full, louder ones attenuated). Returns 1.0 when no
  /// measurement is available so playback never goes silent.
  double volumeForAction(ScriptAction action) {
    if (!_normalizeVolume) return action.effectiveVolume;
    final loudness = _loudness;
    final path = action.filePath;
    if (loudness == null || path == null) return action.effectiveVolume;
    final lMin = minLoudnessDb;
    final lI = loudness.loudnessOf(path);
    if (lMin == null || lI == null) return action.effectiveVolume;
    // v = 10^((L_min - L_i)/20): quietest -> 1.0, louder -> attenuated.
    final v = math.pow(10.0, (lMin - lI) / 20.0).toDouble();
    return v.clamp(0.0, 1.0);
  }

  /// Analyzes (or re-analyzes) [path] and caches the RMS. Returns false when
  /// the platform cannot measure loudness so callers can fall back gracefully.
  Future<bool> ensureLoudness(String path, {bool force = false}) async {
    final loudness = _loudness;
    if (loudness == null) return false;
    final db = await loudness.analyze(path, force: force);
    notifyListeners();
    return db != null;
  }

  /// The cached RMS (dBFS) for a given file path, or null when unknown.
  double? loudnessOf(String path) => _loudness?.loudnessOf(path);

  /// When true the device screen stays on (no auto-lock) so the magnet loop
  /// keeps running and the UI stays responsive over long sessions.
  bool _keepScreenOn = true;
  bool get keepScreenOn => _keepScreenOn;

  // ---------------------------------------------------------------- runtime

  double _magnitude = 0;
  double get magnitude => _magnitude;

  double _fieldX = 0;
  double get fieldX => _fieldX;
  double _fieldY = 0;
  double get fieldY => _fieldY;
  double _fieldZ = 0;
  double get fieldZ => _fieldZ;

  bool _magnetDetected = false;
  bool get magnetDetected => _magnetDetected;

  bool get sensorAvailable => _magnet.status == MagnetStatus.listening;
  MagnetStatus get magnetStatus => _magnet.status;

  bool get scriptRunning => _runner.isRunning;
  int get currentActionIndex => _runner.currentIndex;

  bool get torchOn => _torch.isOn;
  bool get torchAvailable => _torch.available;

  bool get initialized => _initialized;

  static const _sensorNotifyInterval = Duration(milliseconds: 100);
  DateTime _lastSensorNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// The magnitude below which the magnet is considered released again.
  double get releaseThreshold => _detector.releaseThreshold;

  static List<ScriptAction> defaultScript() => const [
    ScriptAction(type: ActionType.torchOn),
    ScriptAction(type: ActionType.delay, delayMs: 1500, lightOn: true),
    ScriptAction(type: ActionType.torchOff),
  ];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
    await _loudness?.load();
    await _torch.checkAvailability();
    _startMagnet();
    _applyVolumeResolver();
    await _applyKeepScreenOn();
    _initialized = true;
    notifyListeners();
  }

  /// Wires the runner's volume resolver to the current [normalizeVolume]
  /// state. Call this whenever the setting or the script set changes.
  void _applyVolumeResolver() {
    if (_normalizeVolume && _loudness != null) {
      _runner.volumeFor = volumeForAction;
    } else {
      _runner.volumeFor = null;
    }
  }

  Future<void> _applyKeepScreenOn() async {
    final cb = _setKeepScreenOnPlatform;
    if (cb == null) return;
    try {
      await cb(_keepScreenOn);
    } catch (_) {
      // Platform channel failures must never block the app.
    }
  }

  // ------------------------------------------------------------- magnet loop

  void _startMagnet() {
    _magnet.onUpdate = notifyListeners;
    _magnet.start();
    _magnetSubscription = _magnet.readings.listen(
      _onReading,
      onError: (Object error) => notifyListeners(),
    );
  }

  void _onReading(MagneticReading reading) {
    final event = _detector.addSample(reading.magnitude);

    _magnitude = reading.magnitude;
    _fieldX = reading.x;
    _fieldY = reading.y;
    _fieldZ = reading.z;
    _magnetDetected = _detector.detected;

    if (event != null && _detectionEnabled) {
      final shouldRun =
          (event == MagnetEvent.approach &&
              _triggerMode == TriggerMode.onApproach) ||
          (event == MagnetEvent.removal &&
              _triggerMode == TriggerMode.onRemoval);
      if (shouldRun) {
        _detector.acknowledgeTrigger();
        unawaited(runScript());
      }
    }

    _notifySensor(force: event != null);
  }

  /// Sensors stream at up to 20 Hz; rebuilding the whole tree on every sample
  /// makes the UI jitter, so readings are coalesced. Discrete changes still
  /// notify immediately through [notifyListeners].
  void _notifySensor({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSensorNotify) < _sensorNotifyInterval) {
      return;
    }
    _lastSensorNotify = now;
    notifyListeners();
  }

  // ------------------------------------------------------------------ script

  /// Runs the script for the current stage.
  ///
  /// Stage logic (variant B): the stage counter is incremented immediately
  /// when a trigger fires, so a new trigger always starts the *next* script.
  /// If the running script contains [ActionType.resetCounter] and completes
  /// without being cancelled, the counter moves to its selected script.
  /// A cancelled script never applies the reset.
  Future<void> runScript() async {
    if (stageBlocked || _scripts.isEmpty) return;

    // A new trigger always interrupts whatever is currently running.
    if (_runner.isRunning) {
      _runner.cancel();
      await _runner.activeRun;
    }

    final stage = _stageIndex;
    _stageIndex++;
    _persist();

    if (_hapticOnScript) unawaited(_hapticFeedback());

    _scriptResetTarget = null;
    _applyVolumeResolver();
    await _runner.run(_scripts[stage], turnOffAtEnd: _turnOffAfterScript);

    // A cancelled run never applies the reset (the flag was cleared above
    // and only set again when the resetCounter step actually executes).
    if (_scriptResetTarget != null) {
      _stageIndex = _scriptResetTarget!;
      _persist();
    }
  }

  int? _scriptResetTarget;

  void _onCounterReset(int target) {
    _scriptResetTarget = target.clamp(0, _scripts.length - 1);
  }

  void stopScript() => _runner.cancel();

  /// Manually rewinds the stage counter to the first script.
  void resetStageCounter() {
    _stageIndex = 0;
    _persist();
  }

  Future<void> toggleTorch() async {
    await _torch.setOn(!_torch.isOn);
    notifyListeners();
  }

  // ------------------------------------------------------------- script edit

  void addScript({bool copyCurrent = false}) {
    final source = (_scripts.isNotEmpty && copyCurrent)
        ? _scripts[_stageIndex.clamp(0, _scripts.length - 1)]
        : defaultScript();
    _scripts = [..._scripts, List.of(source)];
    _persist();
  }

  void removeScript(int index) {
    if (index < 0 || index >= _scripts.length) return;
    final next = [..._scripts]..removeAt(index);
    if (next.isEmpty) next.add(defaultScript());
    _scripts = _remapResetTargets(next, removedIndex: index);
    if (_stageIndex >= _scripts.length) _stageIndex = _scripts.length - 1;
    _persist();
  }

  void duplicateScript(int index) {
    if (index < 0 || index >= _scripts.length) return;
    final next = [..._scripts];
    next.insert(index + 1, List.of(_scripts[index]));
    _scripts = _remapResetTargets(next, insertedIndex: index + 1);
    _persist();
  }

  List<List<ScriptAction>> _remapResetTargets(
    List<List<ScriptAction>> scripts, {
    int? removedIndex,
    int? insertedIndex,
  }) {
    return [
      for (final script in scripts)
        [
          for (final action in script)
            if (action.type != ActionType.resetCounter)
              action
            else
              action.copyWith(
                resetToScriptIndex: removedIndex != null
                    ? action.resetToScriptIndex == removedIndex
                        ? (scripts.length - 1).clamp(0, removedIndex)
                        : action.resetToScriptIndex > removedIndex
                        ? action.resetToScriptIndex - 1
                        : action.resetToScriptIndex
                    : action.resetToScriptIndex >= insertedIndex!
                    ? action.resetToScriptIndex + 1
                    : action.resetToScriptIndex,
              ),
        ],
    ];
  }

  void addAction(ScriptAction action, {int scriptIndex = 0}) {
    if (scriptIndex < 0 || scriptIndex >= _scripts.length) return;
    final next = [..._scripts];
    next[scriptIndex] = [...next[scriptIndex], action];
    _scripts = next;
    _persist();
  }

  void updateAction(
    int scriptIndex,
    int index,
    ScriptAction action,
  ) {
    if (scriptIndex < 0 || scriptIndex >= _scripts.length) return;
    final script = _scripts[scriptIndex];
    if (index < 0 || index >= script.length) return;
    final next = [..._scripts];
    final updated = [...script];
    updated[index] = action;
    next[scriptIndex] = updated;
    _scripts = next;
    _persist();
  }

  void removeAction(int scriptIndex, int index) {
    if (scriptIndex < 0 || scriptIndex >= _scripts.length) return;
    final script = _scripts[scriptIndex];
    if (index < 0 || index >= script.length) return;
    final next = [..._scripts];
    final updated = [...script]..removeAt(index);
    next[scriptIndex] = updated;
    _scripts = next;
    _persist();
  }

  void reorderAction(int scriptIndex, int oldIndex, int newIndex) {
    if (scriptIndex < 0 || scriptIndex >= _scripts.length) return;
    final script = _scripts[scriptIndex];
    if (oldIndex < 0 || oldIndex >= script.length) return;
    if (newIndex < 0 || newIndex >= script.length) return;
    if (oldIndex == newIndex) return;
    final next = [..._scripts];
    final updated = [...script];
    final action = updated.removeAt(oldIndex);
    updated.insert(newIndex, action);
    next[scriptIndex] = updated;
    _scripts = next;
    _persist();
  }

  // ---------------------------------------------------------------- settings

  void setDetectionEnabled(bool value) {
    _detectionEnabled = value;
    _persist();
  }

  void setThreshold(double value) {
    _threshold = value;
    _detector.threshold = value;
    _persist();
  }

  void setTriggerMode(TriggerMode mode) {
    _triggerMode = mode;
    _persist();
  }

  void setTurnOffAfterScript(bool value) {
    _turnOffAfterScript = value;
    _persist();
  }

  void setHapticOnScript(bool value) {
    _hapticOnScript = value;
    _persist();
  }

  void setNormalizeVolume(bool value) {
    _normalizeVolume = value;
    _applyVolumeResolver();
    _persist();
  }

  void setKeepScreenOn(bool value) {
    _keepScreenOn = value;
    _persist();
    unawaited(_applyKeepScreenOn());
  }

  // ------------------------------------------------------------- persistence

  void _load() {
    final prefs = _prefs;
    if (prefs == null) return;

    final rawScripts = prefs.getString(_scriptsKey);
    if (rawScripts != null) {
      try {
        final decoded = jsonDecode(rawScripts) as List<dynamic>;
        final parsed = decoded.map((scriptRaw) {
          final list = scriptRaw as List<dynamic>;
          return list
              .cast<Map<String, dynamic>>()
              .map(ScriptAction.fromJson)
              .toList();
        }).where((s) => s.isNotEmpty).toList();
        if (parsed.isNotEmpty) _scripts = parsed;
      } catch (_) {
        // keep the default script on malformed data
      }
    } else {
      // Migration from the old single-script format.
      final rawScript = prefs.getString(_scriptKey);
      if (rawScript != null) {
        try {
          final decoded = jsonDecode(rawScript) as List<dynamic>;
          final parsed = decoded
              .cast<Map<String, dynamic>>()
              .map(ScriptAction.fromJson)
              .toList();
          if (parsed.isNotEmpty) _scripts = [parsed];
        } catch (_) {
          // keep the default script on malformed data
        }
      }
    }

    _stageIndex = prefs.getInt(_stageIndexKey) ?? 0;
    if (_stageIndex < 0) _stageIndex = 0;
    if (_stageIndex > _scripts.length) _stageIndex = _scripts.length;

    _detectionEnabled = prefs.getBool(_detectionKey) ?? true;
    _threshold = prefs.getDouble(_thresholdKey) ?? 150;
    _detector.threshold = _threshold;
    final modeIndex = prefs.getInt(_triggerModeKey) ?? 0;
    _triggerMode =
        TriggerMode.values[modeIndex.clamp(0, TriggerMode.values.length - 1)];
    _turnOffAfterScript = prefs.getBool(_turnOffKey) ?? true;
    _hapticOnScript = prefs.getBool(_hapticKey) ?? true;
    _normalizeVolume = prefs.getBool(_normalizeVolumeKey) ?? false;
    _keepScreenOn = prefs.getBool(_keepScreenOnKey) ?? true;
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) {
      notifyListeners();
      return;
    }
    prefs.setString(
      _scriptsKey,
      jsonEncode(
        _scripts
            .map((script) => script.map((a) => a.toJson()).toList())
            .toList(),
      ),
    );
    prefs.setInt(_stageIndexKey, _stageIndex);
    prefs.setBool(_detectionKey, _detectionEnabled);
    prefs.setDouble(_thresholdKey, _threshold);
    prefs.setInt(_triggerModeKey, _triggerMode.index);
    prefs.setBool(_turnOffKey, _turnOffAfterScript);
    prefs.setBool(_hapticKey, _hapticOnScript);
    prefs.setBool(_normalizeVolumeKey, _normalizeVolume);
    prefs.setBool(_keepScreenOnKey, _keepScreenOn);
    notifyListeners();
  }

  @override
  void dispose() {
    _magnetSubscription?.cancel();
    _magnet.dispose();
    _torch.setOn(false);
    _music.dispose();
    super.dispose();
  }
}
