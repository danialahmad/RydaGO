import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';

class Auth {
  const Auth(this.token, this.email);
  final String token;
  final String email;
}

/// The logged-in user, kept in local storage so a reload does not log out.
class AuthNotifier extends Notifier<Auth?> {
  @override
  Auth? build() {
    Future.microtask(_restore);
    return null;
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString('token');
      final e = p.getString('email');
      if (t != null && e != null && state == null) state = Auth(t, e);
    } catch (_) {
      // Storage unavailable: the user just logs in again.
    }
  }

  /// Returns an error message to show, or null on success.
  Future<String?> submit({
    required bool register,
    required String email,
    required String password,
  }) async {
    try {
      final (token, confirmedEmail) = await Api.authenticate(
          register: register, email: email, password: password);
      state = Auth(token, confirmedEmail);
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('token', token);
        await p.setString('email', confirmedEmail);
      } catch (_) {}
      return null;
    } on AuthFailure catch (e) {
      return e.message;
    }
  }

  Future<void> logout() async {
    state = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('token');
      await p.remove('email');
    } catch (_) {}
  }
}

final authProvider = NotifierProvider<AuthNotifier, Auth?>(AuthNotifier.new);
