import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/commuter_preference_service.dart';
import 'screens/home_screen.dart';

// Global reference for Supabase queries
final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ghrtgzqtucifnzmfmfjw.supabase.co', // Changed the 'q' to a 'g'
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdocnRnenF0dWNpZm56bWZtZmp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI1OTc2MTksImV4cCI6MjEwODE3MzYxOX0.HQMIyN5pYE3BrQmLvClZD8MWXKaPezG9SVFew8kpheo',
  );

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
          title: 'Mapparaan',
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
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        CommuterPreferencesService.current.value =
            const CommuterPreferences();
        return;
      }
      if (state.session != null) _loadUserPreferences();
    });
  }

  Future<void> _loadUserPreferences() async {
    try {
      await CommuterPreferencesService.load();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while loading commuter preferences'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
