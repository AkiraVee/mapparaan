import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final SupabaseClient _client = Supabase.instance.client;

  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(
    _client.auth.currentSession != null,
  );
  
  // New local state to track if they bypassed the login screen
  static final ValueNotifier<bool> isGuest = ValueNotifier(false);

  static User? get currentUser => _client.auth.currentUser;

  // Let the user bypass the AuthGate without talking to the database
  static void continueAsGuest() {
    isGuest.value = true;
  }

  static Future<void> createAccount(String name, String email, String password) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );

    if (response.user != null) {
      final userId = response.user!.id;

      await _client.from('users').upsert({
        'id': userId,
        'full_name': name,
        'email': email,
      });

      await _client.from('user_preferences').upsert({
        'user_id': userId,
        'passenger_type': 'general',
      });

      isGuest.value = false; // Reset guest mode if they sign up
      isLoggedIn.value = true;
    }
  }

  static Future<void> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      isGuest.value = false; // Reset guest mode if they sign in
      isLoggedIn.value = true;
    }
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
    isGuest.value = false; // Ensure they go back to the login screen
    isLoggedIn.value = false;
  }
}