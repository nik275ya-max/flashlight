import 'package:flutter/material.dart';

import '../services/app_launch_service.dart';

/// Shows a searchable list of the installed apps.
///
/// Returns the picked app, or null when the user closed the dialog.
Future<AppInfo?> showAppPicker(
  BuildContext context, {
  required AppLaunchService service,
  String? selectedPackage,
}) {
  return showDialog<AppInfo>(
    context: context,
    builder: (context) => _AppPickerDialog(
      service: service,
      selectedPackage: selectedPackage,
    ),
  );
}

class _AppPickerDialog extends StatefulWidget {
  const _AppPickerDialog({required this.service, this.selectedPackage});

  final AppLaunchService service;
  final String? selectedPackage;

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  final TextEditingController _searchController = TextEditingController();

  List<AppInfo> _apps = const <AppInfo>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final apps = await widget.service.listApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
      _error = widget.service.lastError;
    });
  }

  List<AppInfo> get _visibleApps {
    final query = _searchController.text;
    return _apps.where((app) => app.matches(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Запустить приложение', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Поиск приложения',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: _buildBody(theme),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _apps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_apps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Запускаемых приложений не найдено')),
      );
    }

    final visible = _visibleApps;
    if (visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Ничего не найдено')),
      );
    }

    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final app = visible[index];
        final selected = app.packageName == widget.selectedPackage;
        return ListTile(
          selected: selected,
          leading: _AppIcon(app: app),
          title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            app.packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: selected
              ? Icon(Icons.check, color: theme.colorScheme.primary)
              : null,
          onTap: () => Navigator.of(context).pop(app),
        );
      },
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app});

  final AppInfo app;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    if (icon == null || icon.isEmpty) {
      return const Icon(Icons.android, size: 32);
    }
    return Image.memory(
      icon,
      width: 32,
      height: 32,
      errorBuilder: (context, error, stack) => const Icon(Icons.android, size: 32),
    );
  }
}
