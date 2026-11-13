import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_channel.dart';

/// A launchable application installed on the device.
class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.label,
    this.icon,
  });

  /// The Android package id, e.g. `com.android.settings`.
  final String packageName;

  /// The user visible name of the app.
  final String label;

  /// The launcher icon as PNG bytes, or null when it could not be rendered.
  final Uint8List? icon;

  factory AppInfo.fromMap(Map<Object?, Object?> map) {
    final icon = map['icon'];
    return AppInfo(
      packageName: (map['packageName'] as String?) ?? '',
      label: (map['label'] as String?) ?? (map['packageName'] as String?) ?? '',
      icon: _asBytes(icon),
    );
  }

  /// The host sends the icon as a byte list; anything else is ignored.
  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  /// Matches the label or the package id, case insensitively.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return label.toLowerCase().contains(needle) ||
        packageName.toLowerCase().contains(needle);
  }
}

/// Lists and starts the apps installed on the device.
///
/// The list is provided by the Android host: it asks the package manager for
/// every app with a launcher entry. Only those apps can be started, so the
/// picker never offers something that would fail later.
///
/// Every failure is captured in [lastError] and never thrown, so a missing
/// package cannot break the script that tried to launch it.
class AppLaunchService {
  // ignore: prefer_initializing_formals
  AppLaunchService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(backgroundChannelName);

  final MethodChannel _channel;

  List<AppInfo>? _cache;

  /// The cached app list, or null when it was not loaded yet.
  List<AppInfo>? get cached => _cache;

  /// The message of the last failed operation.
  String? lastError;

  /// Drops the cached error message.
  void clearError() => lastError = null;

  /// Returns every launchable app, sorted by name.
  ///
  /// The result is cached; pass [force] to load it again. On platforms
  /// without an app list (anything but Android) the list is empty.
  Future<List<AppInfo>> listApps({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    if (!_isAndroid) {
      _cache = const <AppInfo>[];
      return _cache!;
    }
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'listLaunchableApps',
      );
      final apps = <AppInfo>[];
      for (final entry in raw ?? const <Object?>[]) {
        if (entry is Map<Object?, Object?>) apps.add(AppInfo.fromMap(entry));
      }
      _cache = apps;
      return apps;
    } on PlatformException catch (e) {
      lastError = e.message ?? 'Не удалось получить список приложений';
      return const <AppInfo>[];
    } on MissingPluginException {
      lastError = 'Список приложений недоступен на этой платформе';
      return const <AppInfo>[];
    }
  }

  /// Starts the app with the given package id.
  ///
  /// Returns false when the app is not installed or the system refused the
  /// launch. The reason is left in [lastError].
  Future<bool> launch(String packageName) async {
    if (packageName.isEmpty) {
      lastError = 'Приложение не выбрано';
      return false;
    }
    if (!_isAndroid) {
      lastError = 'Запуск приложений доступен только на Android';
      return false;
    }
    try {
      final started = await _channel.invokeMethod<bool>(
        'launchApp',
        <String, Object?>{'packageName': packageName},
      );
      if (started != true) {
        lastError = 'Не удалось запустить приложение';
        return false;
      }
      lastError = null;
      return true;
    } on PlatformException catch (e) {
      lastError = e.message ?? 'Не удалось запустить приложение';
      return false;
    } on MissingPluginException {
      lastError = 'Запуск приложений недоступен на этой платформе';
      return false;
    }
  }

  /// Opens the system page where the "display over other apps" permission is
  /// granted. Without it Android blocks launches from the background.
  Future<bool> openOverlaySettings() async {
    if (!_isAndroid) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openOverlaySettings');
      return opened == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True when the app is allowed to start activities in the background.
  Future<bool> canLaunchInBackground() async {
    if (!_isAndroid) return false;
    try {
      final allowed = await _channel.invokeMethod<bool>('canLaunchInBackground');
      return allowed == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
