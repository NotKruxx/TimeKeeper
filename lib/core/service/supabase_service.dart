// lib/core/service/supabase_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../error/failures.dart';
import '../error/result.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  User?   get currentUser => _client.auth.currentUser;
  bool    get isSignedIn  => currentUser != null;
  String? get uid         => currentUser?.id;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<Result<User>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(email: email.trim(), password: password);
      if (res.user == null) return Result.err(const AuthFailure('Login fallito.'));
      return Result.ok(res.user!);
    } on AuthException catch (e) {
      return Result.err(AuthFailure(_mapAuthError(e.message)));
    } catch (e) {
      return Result.err(AuthFailure(e.toString()));
    }
  }

  Future<Result<User>> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signUp(email: email.trim(), password: password);
      if (res.user == null) return Result.err(const AuthFailure('Registrazione fallita.'));
      return Result.ok(res.user!);
    } on AuthException catch (e) {
      return Result.err(AuthFailure(_mapAuthError(e.message)));
    } catch (e) {
      return Result.err(AuthFailure(e.toString()));
    }
  }

  Future<Result<void>> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      return Result.ok(null);
    } on AuthException catch (e) {
      return Result.err(AuthFailure(_mapAuthError(e.message)));
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  String _mapAuthError(String message) => switch (message) {
        String m when m.contains('Invalid login credentials') => 'Email o password errati.',
        String m when m.contains('Email not confirmed') => 'Conferma la tua email prima di accedere.',
        String m when m.contains('User already registered') => 'Questa email è già registrata.',
        String m when m.contains('Password should be at least') => 'La password deve contenere almeno 6 caratteri.',
        String m when m.contains('network') => 'Errore di rete. Controlla la connessione.',
        _ => message,
      };
}
