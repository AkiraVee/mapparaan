import 'package:flutter/material.dart';

import 'services/commuter_preference_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CommuterPreferencesService.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CommuterPreferences>(
      valueListenable: CommuterPreferencesService.current,
      builder: (context, preferences, _) {
        final palette = preferences.colorPalette;
        final lightColorScheme =
            ColorScheme.fromSeed(
              seedColor: palette.primary,
              brightness: Brightness.light,
            ).copyWith(
              primary: palette.primary,
              onPrimary: palette.onPrimary,
              primaryContainer: palette.container,
              onPrimaryContainer: palette.onContainer,
              secondary: palette.primary,
              onSecondary: palette.onPrimary,
              secondaryContainer: palette.container,
              onSecondaryContainer: palette.onContainer,
            );
        final darkColorScheme =
            ColorScheme.fromSeed(
              seedColor: palette.primary,
              brightness: Brightness.dark,
            ).copyWith(
              primary: palette.primary,
              onPrimary: palette.onPrimary,
              primaryContainer: palette.container,
              onPrimaryContainer: palette.onContainer,
              secondary: palette.primary,
              onSecondary: palette.onPrimary,
              secondaryContainer: palette.container,
              onSecondaryContainer: palette.onContainer,
            );

        return MaterialApp(
          title: 'mapparaan',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: palette.primary,
            scaffoldBackgroundColor: const Color(0xFFF7F9F8),
            cardColor: Colors.white,
            colorScheme: lightColorScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: palette.primary,
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),
            colorScheme: darkColorScheme,
            useMaterial3: true,
          ),
          themeMode: switch (preferences.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
