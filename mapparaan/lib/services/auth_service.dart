import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(
    _clientOrNull?.auth.currentSession != null,
  );

  static final ValueNotifier<bool> isGuest = ValueNotifier(false);

  static User? get currentUser => _clientOrNull?.auth.currentUser;

  static bool get isConfigured => _clientOrNull != null;

  static void continueAsGuest() {
    isGuest.value = true;
  }

  static Future<bool> createAccount(
    String name,
    String email,
    String password,
  ) async {
    final client = _clientOrNull;
    if (client == null) {
      throw StateError(
        'Account sign-in is not configured. Continue as a guest or add the Supabase settings.',
      );
    }
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );

    if (response.user != null && response.session != null) {
      // The manual .upsert() lines have been removed.
      // The Postgres Trigger on your backend handles this securely now!

      isGuest.value = false;
      isLoggedIn.value = true;
      return true;
    }
    isGuest.value = false;
    isLoggedIn.value = false;
    return false;
  }

  static Future<bool> signIn(String email, String password) async {
    final client = _clientOrNull;
    if (client == null) {
      throw StateError(
        'Account sign-in is not configured. Continue as a guest or add the Supabase settings.',
      );
    }
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      isGuest.value = false;
      isLoggedIn.value = true;
      return true;
    }
    return false;
  }

  static Future<void> signOut() async {
    await _clientOrNull?.auth.signOut();
    isGuest.value = false;
    isLoggedIn.value = false;
  }
}
