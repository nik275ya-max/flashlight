import 'package:flutter/material.dart';

/// The kind of step a script can perform.
enum ActionType {
  torchOn,
  torchOff,
  delay,
  playMusic,
  stopMusic,
  launchApp,
  lockButton,
  unlockButton,
  resetCounter,
}

/// A single step in the flash script.
///
/// A step is either turning the torch on, turning it off, waiting for
/// [delayMs] milliseconds, playing a local audio file ([filePath], only for
/// [ActionType.playMusic]) at [volume] (0.0–1.0), stopping audio, starting
/// another app ([packageName], only for [ActionType.launchApp]) or resetting
/// the stage counter back to a selected script.
@immutable
class ScriptAction {
  const ScriptAction({
    required this.type,
    this.delayMs = 1000,
    this.lightOn = false,
    this.filePath,
    this.volume = 1.0,
    this.resetToScriptIndex = 0,
    this.packageName,
    this.appLabel,
  });

  final ActionType type;
  final int delayMs;
  final bool lightOn;
  final String? filePath;

  /// Playback volume for [ActionType.playMusic], clamped to 0.0–1.0.
  final double volume;
  final int resetToScriptIndex;

  /// The Android package id of the app to start ([ActionType.launchApp]).
  final String? packageName;

  /// The user visible name of that app, shown in the script list.
  final String? appLabel;

  bool get isDelay => type == ActionType.delay;

  /// [volume] clamped into the valid 0.0–1.0 range.
  double get effectiveVolume => volume.clamp(0.0, 1.0);

  String get title {
    switch (type) {
      case ActionType.torchOn:
        return 'Включить вспышку';
      case ActionType.torchOff:
        return 'Выключить вспышку';
      case ActionType.delay:
        final duration = delayMs % 1000 == 0
            ? '${delayMs ~/ 1000} с'
            : '$delayMs мс';
        return 'Задержка $duration · свет ${lightOn ? 'вкл' : 'выкл'}';
      case ActionType.playMusic:
        final name = filePath?.split(RegExp(r'[/\\]')).last ?? 'файл не выбран';
        return 'Включить музыку: $name';
      case ActionType.stopMusic:
        return 'Выключить музыку';
      case ActionType.launchApp:
        final name = appLabel?.trim();
        return name == null || name.isEmpty
            ? 'Запустить приложение'
            : 'Запустить приложение: $name';
      case ActionType.lockButton:
        return 'Заблокировать кнопку';
      case ActionType.unlockButton:
        return 'Разблокировать кнопку';
      case ActionType.resetCounter:
        return 'Сброс счётчика';
    }
  }

  /// Volume as a human readable percent, e.g. «80%».
  String get volumeLabel => '${(effectiveVolume * 100).round()}%';

  String get subtitle {
    switch (type) {
      case ActionType.torchOn:
        return 'Фонарик загорается';
      case ActionType.torchOff:
        return 'Фонарик гаснет';
      case ActionType.delay:
        return lightOn
            ? 'Ждать $delayMs мс, фонарик горит'
            : 'Ждать $delayMs мс, фонарик выключен';
      case ActionType.playMusic:
        return 'Проиграть выбранный аудиофайл (громкость $volumeLabel)';
      case ActionType.stopMusic:
        return 'Остановить воспроизведение';
      case ActionType.launchApp:
        final name = appLabel?.trim();
        return name == null || name.isEmpty
            ? 'Приложение не выбрано'
            : 'Открыть $name';
      case ActionType.lockButton:
        return 'Нажатия кнопки фонарика игнорируются';
      case ActionType.unlockButton:
        return 'Нажатия кнопки снова включают фонарик';
      case ActionType.resetCounter:
        return 'Вернуть счётчик на первый скрипт';
    }
  }

  IconData get icon {
    switch (type) {
      case ActionType.torchOn:
        return Icons.flashlight_on;
      case ActionType.torchOff:
        return Icons.flashlight_off;
      case ActionType.delay:
        return Icons.timer_outlined;
      case ActionType.playMusic:
        return Icons.music_note;
      case ActionType.stopMusic:
        return Icons.music_off;
      case ActionType.launchApp:
        return Icons.apps;
      case ActionType.lockButton:
        return Icons.lock;
      case ActionType.unlockButton:
        return Icons.lock_open;
      case ActionType.resetCounter:
        return Icons.restart_alt;
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'delayMs': delayMs,
    'lightOn': lightOn,
    if (type == ActionType.resetCounter)
      'resetToScriptIndex': resetToScriptIndex,
    if (type == ActionType.playMusic) 'volume': effectiveVolume,
    if (filePath != null) 'filePath': filePath,
    if (packageName != null) 'packageName': packageName,
    if (appLabel != null) 'appLabel': appLabel,
  };

  factory ScriptAction.fromJson(Map<String, dynamic> json) {
    final type = ActionType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => ActionType.delay,
    );
    return ScriptAction(
      type: type,
      delayMs: (json['delayMs'] as num?)?.toInt() ?? 1000,
      lightOn: json['lightOn'] as bool? ?? false,
      filePath: json['filePath'] as String?,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      resetToScriptIndex: (json['resetToScriptIndex'] as num?)?.toInt() ?? 0,
      packageName: json['packageName'] as String?,
      appLabel: json['appLabel'] as String?,
    );
  }

  ScriptAction copyWith({
    ActionType? type,
    int? delayMs,
    bool? lightOn,
    String? filePath,
    double? volume,
    int? resetToScriptIndex,
    String? packageName,
    String? appLabel,
  }) {
    return ScriptAction(
      type: type ?? this.type,
      delayMs: delayMs ?? this.delayMs,
      lightOn: lightOn ?? this.lightOn,
      filePath: filePath ?? this.filePath,
      volume: volume ?? this.volume,
      resetToScriptIndex: resetToScriptIndex ?? this.resetToScriptIndex,
      packageName: packageName ?? this.packageName,
      appLabel: appLabel ?? this.appLabel,
    );
  }
}
