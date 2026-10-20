import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

// Global notifier to control Theme Mode (System / Light / Dark) across the app
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'mapparaan',
          debugShowCheckedModeBanner: false,

          // 1. Light Theme Definition
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF00695C),
            scaffoldBackgroundColor: const Color(0xFFF7F9F8),
            cardColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00695C),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),

          // 2. Dark Theme Definition
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF80CBC4),
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00695C),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),

          // Active Mode (Listens to the theme setting)
          themeMode: currentMode,

          home: const HomeScreen(),
        );
      },
    );
  }
}