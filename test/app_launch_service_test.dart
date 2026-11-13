import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flashlight/services/app_launch_service.dart';
import 'package:flashlight/services/platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(backgroundChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  void mockHandler(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    // The service only talks to the host on Android.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  group('AppInfo', () {
    test('parses the payload of the host', () {
      final app = AppInfo.fromMap(const {
        'packageName': 'com.example.app',
        'label': 'Пример',
        'icon': <int>[1, 2, 3],
      });

      expect(app.packageName, 'com.example.app');
      expect(app.label, 'Пример');
      expect(app.icon, isNotNull);
      expect(app.icon!.length, 3);
    });

    test('falls back to the package id when the label is missing', () {
      final app = AppInfo.fromMap(const {'packageName': 'com.example.app'});
      expect(app.label, 'com.example.app');
      expect(app.icon, isNull);
    });

    test('matches the label and the package id', () {
      const app = AppInfo(packageName: 'com.example.app', label: 'Пример');

      expect(app.matches('прим'), isTrue);
      expect(app.matches('EXAMPLE'), isTrue);
      expect(app.matches(''), isTrue);
      expect(app.matches('другое'), isFalse);
    });
  });

  group('AppLaunchService', () {
    test('lists the apps the host reports', () async {
      mockHandler((call) async {
        return <Object?>[
          <Object?, Object?>{
            'packageName': 'com.example.one',
            'label': 'Первое',
          },
          <Object?, Object?>{
            'packageName': 'com.example.two',
            'label': 'Второе',
          },
        ];
      });
      final service = AppLaunchService(channel: channel);

      final apps = await service.listApps();

      expect(apps.length, 2);
      expect(apps.first.packageName, 'com.example.one');
      expect(apps.last.label, 'Второе');
      expect(calls.single.method, 'listLaunchableApps');
    });

    test('caches the list until it is forced to reload', () async {
      mockHandler((call) async {
        return <Object?>[
          <Object?, Object?>{'packageName': 'com.example.one', 'label': 'Первое'},
        ];
      });
      final service = AppLaunchService(channel: channel);

      await service.listApps();
      await service.listApps();

      expect(calls.where((c) => c.method == 'listLaunchableApps').length, 1);

      await service.listApps(force: true);

      expect(calls.where((c) => c.method == 'listLaunchableApps').length, 2);
    });

    test('launches the app by package name', () async {
      mockHandler((call) async => true);
      final service = AppLaunchService(channel: channel);

      final launched = await service.launch('com.example.one');

      expect(launched, isTrue);
      expect(calls.single.method, 'launchApp');
      expect(calls.single.arguments['packageName'], 'com.example.one');
      expect(service.lastError, isNull);
    });

    test('reports a failed launch', () async {
      mockHandler((call) async => false);
      final service = AppLaunchService(channel: channel);

      final launched = await service.launch('com.example.one');

      expect(launched, isFalse);
      expect(service.lastError, isNotNull);
    });

    test('never launches without a package name', () async {
      mockHandler((call) async => true);
      final service = AppLaunchService(channel: channel);

      final launched = await service.launch('');

      expect(launched, isFalse);
      expect(calls, isEmpty);
      expect(service.lastError, isNotNull);
    });

    test('survives a failing host', () async {
      mockHandler((call) async => throw PlatformException(code: 'boom'));
      final service = AppLaunchService(channel: channel);

      final launched = await service.launch('com.example.one');

      expect(launched, isFalse);
      expect(service.lastError, isNotNull);
    });

    test('clears the error message on request', () async {
      mockHandler((call) async => false);
      final service = AppLaunchService(channel: channel);

      await service.launch('com.example.one');
      expect(service.lastError, isNotNull);

      service.clearError();
      expect(service.lastError, isNull);
    });
  });
}
