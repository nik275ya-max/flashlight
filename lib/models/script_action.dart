import 'package:flutter/material.dart';

/// The kind of step a script can perform.
enum ActionType { torchOn, torchOff, delay, playMusic, stopMusic, resetCounter }

/// A single step in the flash script.
///
/// A step is either turning the torch on, turning it off, waiting for
/// [delayMs] milliseconds, playing a local audio file ([filePath], only for
/// [ActionType.playMusic]), stopping audio, or resetting the stage counter
/// back to the first script.
@immutable
class ScriptAction {
  const ScriptAction({
    required this.type,
    this.delayMs = 1000,
    this.lightOn = false,
    this.filePath,
  });

  final ActionType type;
  final int delayMs;
  final bool lightOn;
  final String? filePath;

  bool get isDelay => type == ActionType.delay;

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
      case ActionType.resetCounter:
        return 'Сброс счётчика';
    }
  }

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
        return 'Проиграть выбранный аудиофайл';
      case ActionType.stopMusic:
        return 'Остановить воспроизведение';
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
      case ActionType.resetCounter:
        return Icons.restart_alt;
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'delayMs': delayMs,
    'lightOn': lightOn,
    if (filePath != null) 'filePath': filePath,
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
    );
  }

  ScriptAction copyWith({
    ActionType? type,
    int? delayMs,
    bool? lightOn,
    String? filePath,
  }) {
    return ScriptAction(
      type: type ?? this.type,
      delayMs: delayMs ?? this.delayMs,
      lightOn: lightOn ?? this.lightOn,
      filePath: filePath ?? this.filePath,
    );
  }
}
