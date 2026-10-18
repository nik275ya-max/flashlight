import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/script_action.dart';

/// Shows a bottom sheet to create or edit a single [ScriptAction].
///
/// Returns the edited action, or null if the user cancelled.
Future<ScriptAction?> showActionEditor(
  BuildContext context, {
  ScriptAction? initial,
  int scriptCount = 1,
}) {
  return showModalBottomSheet<ScriptAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ActionEditor(
      initial: initial,
      scriptCount: scriptCount,
    ),
  );
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({this.initial, required this.scriptCount});

  final ScriptAction? initial;
  final int scriptCount;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late ActionType _type;
  late bool _lightOn;
  late String? _filePath;
  late int _resetTarget;
  late final TextEditingController _msController;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initial ?? const ScriptAction(type: ActionType.delay, delayMs: 1000);
    _type = initial.type;
    _lightOn = initial.lightOn;
    _filePath = initial.filePath;
    _resetTarget = initial.resetToScriptIndex.clamp(0, widget.scriptCount - 1);
    _msController = TextEditingController(text: '${initial.delayMs}');
  }

  @override
  void dispose() {
    _msController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Новый шаг' : 'Изменить шаг',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ActionType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Тип шага',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final type in ActionType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_iconFor(type), size: 20),
                        const SizedBox(width: 8),
                        Text(_labelFor(type)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            if (_type == ActionType.delay) ...[
              const SizedBox(height: 24),
              TextField(
                controller: _msController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Задержка в миллисекундах',
                  suffixText: 'мс',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _lightOn,
                onChanged: (value) => setState(() => _lightOn = value),
                title: const Text('Свет включён во время задержки'),
                subtitle: Text(
                  _lightOn
                      ? 'Фонарик горит всё время паузы'
                      : 'Фонарик выключен всё время паузы',
                ),
              ),
            ],
            if (_type == ActionType.playMusic) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _filePath == null ? 'Выбрать аудиофайл' : _fileName(_filePath!),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_filePath != null) ...[
                const SizedBox(height: 8),
                Text(
                  _filePath!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
            if (_type == ActionType.resetCounter) ...[
              const SizedBox(height: 24),
              DropdownButtonFormField<int>(
                initialValue: _resetTarget,
                decoration: const InputDecoration(
                  labelText: 'Target script',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var i = 0; i < widget.scriptCount; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('Script ${i + 1}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _resetTarget = value);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'После выполнения этого шага счётчик срабатываний '
                'вернётся на первый скрипт.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  String _labelFor(ActionType type) {
    switch (type) {
      case ActionType.torchOn:
        return 'Включить вспышку';
      case ActionType.torchOff:
        return 'Выключить вспышку';
      case ActionType.delay:
        return 'Задержка';
      case ActionType.playMusic:
        return 'Включить музыку';
      case ActionType.stopMusic:
        return 'Выключить музыку';
      case ActionType.resetCounter:
        return 'Сброс счётчика';
    }
  }

  IconData _iconFor(ActionType type) {
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

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path != null) {
      setState(() => _filePath = path);
    }
  }

  void _save() {
    var delayMs = int.tryParse(_msController.text) ?? 0;
    if (delayMs < 1) delayMs = 1;
    if (delayMs > 3600000) delayMs = 3600000;

    final action = ScriptAction(
      type: _type,
      delayMs: delayMs,
      lightOn: _type == ActionType.delay
          ? _lightOn
          : _type == ActionType.torchOn,
      filePath: _type == ActionType.playMusic ? _filePath : null,
      resetToScriptIndex: _type == ActionType.resetCounter ? _resetTarget : 0,
    );
    Navigator.of(context).pop(action);
  }
}
