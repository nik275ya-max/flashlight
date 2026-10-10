import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../models/script_action.dart';
import '../widgets/action_editor.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final script = controller.script;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(
            title: 'Скрипт',
            subtitle: 'Соберите последовательность любым количеством шагов. Она запустится при срабатывании магнитометра.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AddButton(
                  icon: Icons.flashlight_on,
                  label: 'Включить',
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
                  label: 'Выключить',
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
              onReorderItem: controller.reorderAction,
              children: [
                for (var i = 0; i < script.length; i++)
                  _ActionTile(
                    key: ValueKey(
                      'action-$i-${script[i].type.name}-${script[i].delayMs}',
                    ),
                    index: i,
                    action: script[i],
                    onEdit: () => _edit(context, controller, i),
                    onDelete: () => controller.removeAction(i),
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
    controller.addAction(action);
    _showAddedHint(context);
  }

  Future<void> _addDelay(BuildContext context, AppController controller) async {
    final action = await showActionEditor(
      context,
      initial: const ScriptAction(type: ActionType.delay, delayMs: 1000),
    );
    if (action != null) controller.addAction(action);
  }

  Future<void> _edit(
    BuildContext context,
    AppController controller,
    int index,
  ) async {
    final action = await showActionEditor(
      context,
      initial: controller.script[index],
    );
    if (action != null) controller.updateAction(index, action);
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
