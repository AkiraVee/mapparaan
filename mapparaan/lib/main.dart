import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/commuter_preference_service.dart';
import 'services/local_ui_preferences_service.dart';
import 'services/memory_pin_service.dart';
import 'services/friend_sharing_service.dart';
import 'screens/home_screen.dart';
import 'screens/legal_acknowledgement_screen.dart';
import 'constants.dart';
import 'services/auth_service.dart';
import 'services/legal_acknowledgement_service.dart';

// Resolve the client lazily. Accessing Supabase.instance.client at top-level
// would happen before Supabase.initialize() during application startup.
SupabaseClient get supabase => Supabase.instance.client;
bool supabaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? configurationError;
  try {
    await dotenv.load(fileName: '.env.client');
  } catch (error) {
    configurationError = 'Local cloud configuration is unavailable.';
  }

  if (configurationError == null) {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        publishableKey: AppConstants.supabaseClientKey,
      );
    } catch (_) {
      configurationError = 'Cloud services are unavailable.';
    }
  }

  if (configurationError == null) {
    supabaseReady = true;
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
                final appChild = child!;
                final content = filter == ColorVisionFilter.none
                    ? appChild
                    : ColorFiltered(
                        colorFilter: ColorFilter.matrix(filter.matrix),
                        child: appChild,
                      );
                return MediaQuery.withClampedTextScaling(
                  minScaleFactor: localPreferences.seniorMode ? 1.15 : 1,
                  child: content,
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
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: palette.primary,
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),
            colorScheme: darkColorScheme,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
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
  bool _checkingAcknowledgements = false;
  bool? _hasCurrentAcknowledgements;
  String? _acknowledgementError;
  bool _accountDataLoaded = false;
  int _acknowledgementCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (!supabaseReady) return;
    final initialSession = supabase.auth.currentSession;
    _activeUserId = initialSession?.user.id;
    AuthService.isLoggedIn.value = initialSession != null;
    AuthService.isGuest.value = false;
    if (initialSession != null) {
      _checkAcknowledgements(initialSession.user.id);
    } else {
      _clearAccountData();
    }

    _authSubscription = supabase.auth.onAuthStateChange.listen((state) {
      AuthService.isLoggedIn.value = state.session != null;
      if (state.session != null) AuthService.isGuest.value = false;
      if (state.event == AuthChangeEvent.signedOut) {
        _acknowledgementCheckGeneration++;
        _activeUserId = null;
        _hasCurrentAcknowledgements = null;
        _acknowledgementError = null;
        _checkingAcknowledgements = false;
        _accountDataLoaded = false;
        _clearAccountData();
        if (mounted) setState(() {});
        return;
      }

      final sessionUserId = state.session?.user.id;
      if (state.event == AuthChangeEvent.initialSession) {
        if (sessionUserId == null) {
          _activeUserId = null;
          _hasCurrentAcknowledgements = null;
          _accountDataLoaded = false;
          _clearAccountData();
        } else if (sessionUserId != _activeUserId) {
          _activeUserId = sessionUserId;
          _hasCurrentAcknowledgements = null;
          _accountDataLoaded = false;
          _clearAccountData();
          _checkAcknowledgements(sessionUserId);
        }
        return;
      }

      if (sessionUserId != null &&
          (state.event == AuthChangeEvent.signedIn ||
              sessionUserId != _activeUserId)) {
        if (sessionUserId != _activeUserId) _clearAccountData();
        if (sessionUserId != _activeUserId) {
          _hasCurrentAcknowledgements = null;
          _accountDataLoaded = false;
        }
        _activeUserId = sessionUserId;
        _checkAcknowledgements(sessionUserId);
      }
    });
  }

  Future<void> _checkAcknowledgements(String userId) async {
    final generation = ++_acknowledgementCheckGeneration;
    if (mounted) {
      setState(() {
        _checkingAcknowledgements = true;
        _acknowledgementError = null;
      });
    } else {
      _checkingAcknowledgements = true;
      _acknowledgementError = null;
    }

    try {
      final hasCurrent =
          await LegalAcknowledgementService.hasCurrentAcknowledgements();
      if (!mounted ||
          generation != _acknowledgementCheckGeneration ||
          _activeUserId != userId) {
        return;
      }
      setState(() {
        _checkingAcknowledgements = false;
        _hasCurrentAcknowledgements = hasCurrent;
      });
      if (hasCurrent && !_accountDataLoaded) {
        _accountDataLoaded = true;
        _loadAccountData();
      }
    } catch (error, stackTrace) {
      if (!mounted ||
          generation != _acknowledgementCheckGeneration ||
          _activeUserId != userId) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while checking legal acknowledgements'),
        ),
      );
      setState(() {
        _checkingAcknowledgements = false;
        _acknowledgementError = 'We could not verify the current notices. Check your connection and try again.';
      });
    }
  }

  void _onAcknowledged() {
    final userId = _activeUserId;
    if (userId != null) _checkAcknowledgements(userId);
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
    if (supabaseReady && _activeUserId != null) {
      if (_checkingAcknowledgements ||
          (_hasCurrentAcknowledgements == null &&
              _acknowledgementError == null)) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_acknowledgementError != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_acknowledgementError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _checkAcknowledgements(_activeUserId!),
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (_hasCurrentAcknowledgements == false) {
        return LegalAcknowledgementScreen(
          key: ValueKey(_activeUserId),
          onAcknowledged: _onAcknowledged,
          onSignOut: supabase.auth.signOut,
        );
      }
    }
    return const HomeScreen();
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while signing out from AuthGate'),
        ),
      );
      if (mounted) {
        setState(() {
          _acknowledgementError =
              'We could not sign you out. Check your connection and try again.';
        });
      }
    }
  }
}
