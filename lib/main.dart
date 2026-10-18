import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
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

  final controller = AppController(
    torchService: TorchService(),
    magnetService: MagnetService(),
  );
  await controller.init();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    const channel = MethodChannel('com.magictech.flashlight/background');
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
