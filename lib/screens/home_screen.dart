import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import 'settings_screen.dart';

const _darkBackground = Color(0xFF121212);
const _litBackground = Color(0xFFFFF6DC);
const _litForeground = Color(0xFF1C1B17);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final lit = controller.torchOn;

    return Scaffold(
      backgroundColor: lit ? _litBackground : _darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: lit ? _litForeground : Colors.white,
        title: Text(
          'Flashlight',
          style: TextStyle(
            color: lit ? _litForeground : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: Icon(
              Icons.settings,
              color: lit ? _litForeground : Colors.white,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PowerButton(controller: controller, lit: lit),
              const SizedBox(height: 40),
              _StatusText(controller: controller, lit: lit),
            ],
          ),
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.controller, required this.lit});

  final AppController controller;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final available = controller.torchAvailable;
    final surface = lit ? const Color(0xFF2B2416) : const Color(0xFF242424);
    final iconColor = lit ? const Color(0xFFFFC94D) : Colors.white38;

    return Semantics(
      button: true,
      label: lit ? 'Выключить фонарик' : 'Включить фонарик',
      child: GestureDetector(
        onTap: available ? controller.toggleTorch : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surface,
            boxShadow: lit
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFC24D).withValues(alpha: 0.45),
                      blurRadius: 90,
                      spreadRadius: 20,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 40,
                    ),
                  ],
          ),
          child: Icon(
            Icons.power_settings_new,
            size: 104,
            color: available ? iconColor : Colors.white12,
          ),
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.controller, required this.lit});

  final AppController controller;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (!controller.torchAvailable) {
      text = 'Вспышка недоступна на этом устройстве';
    } else if (controller.scriptRunning) {
      text = 'Выполняется скрипт…';
    } else if (lit) {
      text = 'Фонарик включён';
    } else {
      text = 'Нажмите, чтобы включить';
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        color: lit ? _litForeground.withValues(alpha: 0.75) : Colors.white54,
      ),
    );
  }
}
