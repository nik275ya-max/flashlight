import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class FlashlightApp extends StatelessWidget {
  const FlashlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Flashlight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: colorScheme),
      home: const HomeScreen(),
    );
  }
}
