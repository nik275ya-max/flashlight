import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/script_action.dart';
import '../services/magnet_detector.dart';
import '../services/magnet_service.dart';
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

/// Central application state: the script, the detection settings and the live
/// magnetometer values.
class AppController extends ChangeNotifier {
  AppController({
    required TorchService torchService,
    required MagnetService magnetService,
  }) : _torch = torchService,
       _magnet = magnetService {
    _runner = ScriptRunner(_torch);
    _runner.onUpdate = notifyListeners;
    _detector = MagnetDetector(threshold: _threshold);
  }

  final TorchService _torch;
  final MagnetService _magnet;
  late final ScriptRunner _runner;
  late final MagnetDetector _detector;

  StreamSubscription<MagneticReading>? _magnetSubscription;
  SharedPreferences? _prefs;
  bool _initialized = false;

  static const _thresholdKey = 'threshold';
  static const _detectionKey = 'detectionEnabled';
  static const _triggerModeKey = 'triggerMode';
  static const _turnOffKey = 'turnOffAfterScript';
  static const _scriptKey = 'script';

  // ---------------------------------------------------------------- settings

  List<ScriptAction> _script = defaultScript();
  List<ScriptAction> get script => List.unmodifiable(_script);

  bool _detectionEnabled = true;
  bool get detectionEnabled => _detectionEnabled;

  double _threshold = 150;
  double get threshold => _threshold;

  TriggerMode _triggerMode = TriggerMode.onApproach;
  TriggerMode get triggerMode => _triggerMode;

  bool _turnOffAfterScript = true;
  bool get turnOffAfterScript => _turnOffAfterScript;

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

  static const _sensorNotifyInterval = Duration(milliseconds: 200);
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
    await _torch.checkAvailability();
    _startMagnet();
    _initialized = true;
    notifyListeners();
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

    _magnitude = _detector.filtered;
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

  Future<void> runScript() async {
    if (_runner.isRunning) return;
    await _runner.run(_script, turnOffAtEnd: _turnOffAfterScript);
  }

  void stopScript() => _runner.cancel();

  Future<void> toggleTorch() async {
    await _torch.setOn(!_torch.isOn);
    notifyListeners();
  }

  // ------------------------------------------------------------- script edit

  void addAction(ScriptAction action) {
    _script = [..._script, action];
    _persist();
  }

  void updateAction(int index, ScriptAction action) {
    if (index < 0 || index >= _script.length) return;
    final next = [..._script];
    next[index] = action;
    _script = next;
    _persist();
  }

  void removeAction(int index) {
    if (index < 0 || index >= _script.length) return;
    final next = [..._script]..removeAt(index);
    _script = next;
    _persist();
  }

  void reorderAction(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _script.length) return;
    if (newIndex < 0 || newIndex >= _script.length) return;
    if (oldIndex == newIndex) return;
    final next = [..._script];
    final action = next.removeAt(oldIndex);
    next.insert(newIndex, action);
    _script = next;
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

  // ------------------------------------------------------------- persistence

  void _load() {
    final prefs = _prefs;
    if (prefs == null) return;

    final rawScript = prefs.getString(_scriptKey);
    if (rawScript != null) {
      try {
        final decoded = jsonDecode(rawScript) as List<dynamic>;
        final parsed = decoded
            .cast<Map<String, dynamic>>()
            .map(ScriptAction.fromJson)
            .toList();
        if (parsed.isNotEmpty) _script = parsed;
      } catch (_) {
        // keep the default script on malformed data
      }
    }

    _detectionEnabled = prefs.getBool(_detectionKey) ?? true;
    _threshold = prefs.getDouble(_thresholdKey) ?? 150;
    _detector.threshold = _threshold;
    final modeIndex = prefs.getInt(_triggerModeKey) ?? 0;
    _triggerMode =
        TriggerMode.values[modeIndex.clamp(0, TriggerMode.values.length - 1)];
    _turnOffAfterScript = prefs.getBool(_turnOffKey) ?? true;
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) {
      notifyListeners();
      return;
    }
    prefs.setString(
      _scriptKey,
      jsonEncode(_script.map((action) => action.toJson()).toList()),
    );
    prefs.setBool(_detectionKey, _detectionEnabled);
    prefs.setDouble(_thresholdKey, _threshold);
    prefs.setInt(_triggerModeKey, _triggerMode.index);
    prefs.setBool(_turnOffKey, _turnOffAfterScript);
    notifyListeners();
  }

  @override
  void dispose() {
    _magnetSubscription?.cancel();
    _magnet.dispose();
    _torch.setOn(false);
    super.dispose();
  }
}
