import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../models/script_action.dart';
import '../widgets/action_editor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedScript = 0;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scripts = controller.scripts;
    if (_selectedScript >= scripts.length) {
      _selectedScript = scripts.length - 1;
    }
    if (_selectedScript < 0) _selectedScript = 0;
    final script = scripts[_selectedScript];

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(
            title: 'Скрипты',
            subtitle:
                'Магнит запускает скрипты по очереди: сначала №1, затем №2 и т.д. '
                'После последнего — стоп, пока не сбросите счётчик.',
          ),
          const SizedBox(height: 12),
          _ScriptChips(
            count: scripts.length,
            selected: _selectedScript,
            stageIndex: controller.stageIndex,
            stageBlocked: controller.stageBlocked,
            onSelect: (i) => setState(() => _selectedScript = i),
            onAdd: () {
              controller.addScript();
              setState(() => _selectedScript = scripts.length);
            },
            onDuplicate: (i) {
              controller.duplicateScript(i);
              setState(() => _selectedScript = i + 1);
            },
            onRemove: (i) {
              controller.removeScript(i);
              setState(() {
                if (_selectedScript >= i && _selectedScript > 0) {
                  _selectedScript--;
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(
                controller.stageBlocked ? Icons.block : Icons.flag,
                color: controller.stageBlocked
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(controller.stageLabel),
              trailing: TextButton(
                onPressed: controller.resetStageCounter,
                child: const Text('Сброс'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AddButton(
                  icon: Icons.flashlight_on,
                  label: 'Вкл',
                  onPressed: () => _add(
                    context,
                    controller,
                    const ScriptAction(type: ActionType.torchOn),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AddButton(
                  icon: Icons.flashlight_off,
                  label: 'Выкл',
                  onPressed: () => _add(
                    context,
                    controller,
                    const ScriptAction(type: ActionType.torchOff),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AddButton(
                  icon: Icons.timer_outlined,
                  label: 'Задержка',
                  onPressed: () => _addDelay(context, controller),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AddButton(
                  icon: Icons.music_note,
                  label: 'Музыка',
                  onPressed: () => _addMusic(context, controller),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AddButton(
                  icon: Icons.music_off,
                  label: 'Стоп-музыка',
                  onPressed: () => _add(
                    context,
                    controller,
                    const ScriptAction(type: ActionType.stopMusic),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AddButton(
                  icon: Icons.restart_alt,
                  label: 'Сброс сч.',
                  onPressed: () => _add(
                    context,
                    controller,
                    const ScriptAction(type: ActionType.resetCounter),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (script.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Пока нет шагов. Добавьте первый кнопками выше.'),
              ),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) =>
                  controller.reorderAction(_selectedScript, oldIndex, newIndex),
              children: [
                for (var i = 0; i < script.length; i++)
                  _ActionTile(
                    key: ValueKey(
                      'action-$_selectedScript-$i-${script[i].type.name}-'
                      '${script[i].delayMs}-${script[i].filePath ?? ''}',
                    ),
                    index: i,
                    action: script[i],
                    onEdit: () => _edit(context, controller, i),
                    onDelete: () => controller.removeAction(_selectedScript, i),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          const Divider(),
          _SectionTitle(
            title: 'Порог срабатывания',
            subtitle: 'Скрипт запустится, когда напряжённость магнитного поля превысит это значение.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        controller.magnetDetected
                            ? Icons.sensors
                            : Icons.sensors_off,
                        color: controller.magnetDetected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Сейчас: ${controller.magnitude.toStringAsFixed(0)} µT',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        controller.magnetDetected ? 'ОБНАРУЖЕН' : 'нет',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: controller.magnetDetected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Порог: ${controller.threshold.toStringAsFixed(0)} µT',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Земля ~25–65 µT',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: controller.threshold.clamp(40, 300),
                    min: 40,
                    max: 300,
                    divisions: 260,
                    label: '${controller.threshold.toStringAsFixed(0)} µT',
                    onChanged: controller.setThreshold,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          _SectionTitle(
            title: 'Отклик',
            subtitle: 'Короткий виброотклик, когда магнит запускает скрипт.',
          ),
          Card(
            child: SwitchListTile(
              title: const Text('Вибрация при запуске скрипта'),
              subtitle: const Text('Один короткий отклик на каждый запуск'),
              value: controller.hapticOnScript,
              onChanged: controller.setHapticOnScript,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    AppController controller,
    ScriptAction action,
  ) async {
    controller.addAction(action, scriptIndex: _selectedScript);
    if (context.mounted) _showAddedHint(context);
  }

  Future<void> _addDelay(BuildContext context, AppController controller) async {
    final action = await showActionEditor(
      context,
      initial: const ScriptAction(type: ActionType.delay, delayMs: 1000),
      scriptCount: controller.scripts.length,
    );
    if (action != null) {
      controller.addAction(action, scriptIndex: _selectedScript);
    }
  }

  Future<void> _addMusic(BuildContext context, AppController controller) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    controller.addAction(
      ScriptAction(type: ActionType.playMusic, filePath: path),
      scriptIndex: _selectedScript,
    );
    if (context.mounted) _showAddedHint(context);
  }

  Future<void> _edit(
    BuildContext context,
    AppController controller,
    int index,
  ) async {
    final action = await showActionEditor(
      context,
      initial: controller.scripts[_selectedScript][index],
      scriptCount: controller.scripts.length,
    );
    if (action != null) {
      controller.updateAction(_selectedScript, index, action);
    }
  }

  void _showAddedHint(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 900),
          content: Text('Шаг добавлен в конец скрипта'),
        ),
      );
  }
}

class _ScriptChips extends StatelessWidget {
  const _ScriptChips({
    required this.count,
    required this.selected,
    required this.stageIndex,
    required this.stageBlocked,
    required this.onSelect,
    required this.onAdd,
    required this.onDuplicate,
    required this.onRemove,
  });

  final int count;
  final int selected;
  final int stageIndex;
  final bool stageBlocked;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onDuplicate;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onLongPress: () => _showMenu(context, i),
            child: FilterChip(
              label: Text('${i + 1}'),
              selected: selected == i,
              avatar: i == stageIndex && !stageBlocked
                  ? const Icon(Icons.flag, size: 16)
                  : null,
              onSelected: (_) => onSelect(i),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('+'),
          onPressed: onAdd,
        ),
      ],
    );
  }

  Future<void> _showMenu(BuildContext context, int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Дублировать скрипт'),
              onTap: () => Navigator.of(context).pop('duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить скрипт'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'duplicate') onDuplicate(index);
    if (action == 'delete') onRemove(index);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.index,
    required this.action,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final ScriptAction action;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(action.icon, size: 20),
        ),
        title: Text(action.title),
        subtitle: Text('Шаг ${index + 1}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
