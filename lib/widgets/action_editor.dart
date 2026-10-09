import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/script_action.dart';

/// Shows a bottom sheet to create or edit a single [ScriptAction].
///
/// Returns the edited action, or null if the user cancelled.
Future<ScriptAction?> showActionEditor(
  BuildContext context, {
  ScriptAction? initial,
}) {
  return showModalBottomSheet<ScriptAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ActionEditor(initial: initial),
  );
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({this.initial});

  final ScriptAction? initial;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late ActionType _type;
  late bool _lightOn;
  late final TextEditingController _msController;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initial ??
        const ScriptAction(type: ActionType.delay, delayMs: 1000);
    _type = initial.type;
    _lightOn = initial.lightOn;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initial == null ? 'Новый шаг' : 'Изменить шаг',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SegmentedButton<ActionType>(
            segments: const [
              ButtonSegment(
                value: ActionType.torchOn,
                icon: Icon(Icons.flashlight_on),
                label: Text('Вкл'),
              ),
              ButtonSegment(
                value: ActionType.torchOff,
                icon: Icon(Icons.flashlight_off),
                label: Text('Выкл'),
              ),
              ButtonSegment(
                value: ActionType.delay,
                icon: Icon(Icons.timer_outlined),
                label: Text('Задержка'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (selection) {
              setState(() => _type = selection.first);
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
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Сохранить'),
          ),
        ],
      ),
    );
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
    );
    Navigator.of(context).pop(action);
  }
}
