import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/conversations/conversations_screen.dart';
import 'features/lock/lock_gate.dart';

class OwenApp extends StatelessWidget {
  const OwenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Use the system's Material You palette when the device provides it;
        // otherwise fall back to the neutral minimalist scheme.
        final light = lightDynamic != null
            ? AppTheme.themeFrom(lightDynamic.harmonized())
            : AppTheme.light();
        final dark = darkDynamic != null
            ? AppTheme.themeFrom(darkDynamic.harmonized())
            : AppTheme.dark();

        return MaterialApp(
          title: 'Owen',
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: ThemeMode.system,
          home: const LockGate(child: ConversationsScreen()),
        );
      },
    );
  }
}
