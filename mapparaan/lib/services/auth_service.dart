import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final SupabaseClient _client = Supabase.instance.client;

  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(
    _client.auth.currentSession != null,
  );
  
  static final ValueNotifier<bool> isGuest = ValueNotifier(false);

  static User? get currentUser => _client.auth.currentUser;

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
      // The manual .upsert() lines have been removed. 
      // The Postgres Trigger on your backend handles this securely now!
      
      isGuest.value = false;
      isLoggedIn.value = true;
    }
  }

  static Future<void> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      isGuest.value = false;
      isLoggedIn.value = true;
    }
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
    isGuest.value = false; 
    isLoggedIn.value = false;
  }
}