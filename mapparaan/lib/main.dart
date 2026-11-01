import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/commuter_preference_service.dart';
import 'services/local_ui_preferences_service.dart';
import 'services/memory_pin_service.dart';
import 'services/friend_sharing_service.dart';
import 'screens/home_screen.dart';
import 'constants.dart';
import 'services/auth_service.dart';

// Resolve the client lazily. Accessing Supabase.instance.client at top-level
// would happen before Supabase.initialize() during application startup.
SupabaseClient get supabase => Supabase.instance.client;
bool supabaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load client configuration before initializing Supabase. A missing local
  // file is handled below so tests and a first launch can show a useful error.
  String? configurationError;
  try {
    await dotenv.load(fileName: '.env');
  } catch (error) {
    configurationError = 'Local cloud configuration is unavailable.';
  }

  if (configurationError == null) {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        publishableKey: AppConstants.supabaseClientKey,
      );
    } catch (error) {
      configurationError = 'Cloud services are unavailable: $error';
    }
  }

  if (configurationError == null) {
    supabaseReady = true;
    try {
      await CommuterPreferencesService.load();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription(
            'while loading initial commuter preferences',
          ),
        ),
      );
    }
  } else {
    // The map, search, location, and local route cache remain usable without
    // cloud configuration. Account-backed features fail gracefully in their
    // own services instead of blocking the whole application.
    debugPrint(configurationError);
  }
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
          builder: (context, child) {
            return ValueListenableBuilder<LocalUiPreferences>(
              valueListenable: LocalUiPreferencesService.current,
              builder: (context, localPreferences, child) {
                final filter = localPreferences.colorVisionFilter;
                if (filter == ColorVisionFilter.none) return child!;
                return ColorFiltered(
                  colorFilter: ColorFilter.matrix(filter.matrix),
                  child: child,
                );
              },
              child: child,
            );
          },
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
  StreamSubscription<AuthState>? _authSubscription;
  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    if (!supabaseReady) return;
    final initialSession = supabase.auth.currentSession;
    _activeUserId = initialSession?.user.id;
    AuthService.isLoggedIn.value = initialSession != null;
    AuthService.isGuest.value = false;
    if (initialSession != null) {
      _loadAccountData(loadPreferences: false);
    } else {
      _clearAccountData();
    }

    _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
      AuthService.isLoggedIn.value = state.session != null;
      if (state.session != null) AuthService.isGuest.value = false;
      if (state.event == AuthChangeEvent.signedOut) {
        _activeUserId = null;
        _clearAccountData();
        return;
      }

      final sessionUserId = state.session?.user.id;
      if (state.event == AuthChangeEvent.initialSession) {
        if (sessionUserId == null) {
          _activeUserId = null;
          _clearAccountData();
        } else if (sessionUserId != _activeUserId) {
          _activeUserId = sessionUserId;
          _clearAccountData();
          _loadAccountData();
        }
        return;
      }

      if (sessionUserId != null &&
          (state.event == AuthChangeEvent.signedIn ||
              sessionUserId != _activeUserId)) {
        if (sessionUserId != _activeUserId) _clearAccountData();
        _activeUserId = sessionUserId;
        _loadAccountData();
      }
    });
  }

  void _loadAccountData({bool loadPreferences = true}) {
    if (loadPreferences) _loadUserPreferences();
    _loadMemoryPins();
    _loadSharedMemoryPhotos();
  }

  void _clearAccountData() {
    CommuterPreferencesService.clearForAuthChange();
    MemoryPinService.clearForAuthChange();
    FriendSharingService.clearSharedPhotos();
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

  Future<void> _loadMemoryPins() async {
    try {
      await MemoryPinService.loadMemoryPins();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while loading memory photos'),
        ),
      );
    }
  }

  Future<void> _loadSharedMemoryPhotos() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      FriendSharingService.clearSharedPhotos();
      return;
    }
    try {
      await FriendSharingService.refreshSharedPhotos();
    } catch (error, stackTrace) {
      if (supabase.auth.currentUser?.id != userId) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while loading shared memory photos'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
