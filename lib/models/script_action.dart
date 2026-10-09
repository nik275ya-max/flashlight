import 'package:flutter/material.dart';

/// The kind of step a script can perform.
enum ActionType { torchOn, torchOff, delay }

/// A single step in the flash script.
///
/// A step is either turning the torch on, turning it off, or waiting for
/// [delayMs] milliseconds. When it is a delay, [lightOn] defines whether the
/// torch must be lit during the wait.
@immutable
class ScriptAction {
  const ScriptAction({
    required this.type,
    this.delayMs = 1000,
    this.lightOn = false,
  });

  final ActionType type;
  final int delayMs;
  final bool lightOn;

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
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'delayMs': delayMs,
    'lightOn': lightOn,
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
    );
  }

  ScriptAction copyWith({ActionType? type, int? delayMs, bool? lightOn}) {
    return ScriptAction(
      type: type ?? this.type,
      delayMs: delayMs ?? this.delayMs,
      lightOn: lightOn ?? this.lightOn,
    );
  }
}
