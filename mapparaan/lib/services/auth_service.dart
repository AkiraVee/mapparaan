import 'package:flutter/foundation.dart';

class AuthService {
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
  static Map<String, String> currentUser = {};

  // Updated to accept the new 'name' parameter
  static void createAccount(String name, String email, String password) {
    currentUser = {
      'name': name,
      'email': email,
      'password': password,
    };
    isLoggedIn.value = true;
  }

  static void signIn(String email, String password) {
    currentUser = {
      'name': 'Commuter', // Fallback name if signing into a mock account
      'email': email,
    };
    isLoggedIn.value = true;
  }

  static void signOut() {
    currentUser = {};
    isLoggedIn.value = false;
  }
}