import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'services/loudness_service.dart';
import 'services/magnet_service.dart';
import 'services/torch_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The Android torch API (CameraManager.setTorchMode) requires the CAMERA
  // permission. iOS does not need it for the torch.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Permission.camera.request();
    await Permission.notification.request();
  }

  const channel = MethodChannel('com.magictech.flashlight/background');

  Future<void> setKeepScreenOnPlatform(bool keepOn) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('setKeepScreenOn', {'keepOn': keepOn});
    } on PlatformException {
      // Best effort: the magnet loop still works without the screen flag.
    }
  }

  final controller = AppController(
    torchService: TorchService(),
    magnetService: MagnetService(),
    loudnessService: LoudnessService(channel: channel),
    setKeepScreenOnPlatform: setKeepScreenOnPlatform,
  );
  await controller.init();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await channel.invokeMethod<void>('start');
    } on PlatformException {
      // The foreground service is an Android optimization; sensor errors are
      // still handled by MagnetService when it is unavailable.
    }
  }

  runApp(
    ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: const FlashlightApp(),
    ),
  );
}
