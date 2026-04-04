// lib/ui/pages/login_page.dart

import 'package:flutter/foundation.dart'; // Aggiunto per kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Aggiunto per il client auth

import '../../core/service/supabase_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLogin      = true;   // true = login, false = registrazione
  bool _isLoading    = false;
  bool _obscurePass  = true;
  String? _errorMsg;
  String? _successMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Email + Password ──────────────────────────────────────────────────────

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMsg = null; _successMsg = null; });

    try {
      if (_isLogin) {
        final res = await SupabaseService.instance.signInWithEmail(
          email:    _emailCtrl.text,
          password: _passwordCtrl.text,
        );
        if (res.isErr) {
          setState(() => _errorMsg = res.failure.message);
          return;
        }
        if (mounted) Phoenix.rebirth(context);
      } else {
        final res = await SupabaseService.instance.registerWithEmail(
          email:    _emailCtrl.text,
          password: _passwordCtrl.text,
        );
        if (res.isErr) {
          setState(() => _errorMsg = res.failure.message);
          return;
        }
        setState(() {
          _successMsg = 'Registrazione completata! Controlla la tua email per verificare l\'account, poi accedi.';
          _isLogin = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Password reset ────────────────────────────────────────────────────────

  Future<void> _sendPasswordReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMsg = 'Inserisci la tua email per recuperare la password.');
      return;
    }
    setState(() { _isLoading = true; _errorMsg = null; _successMsg = null; });
    final res = await SupabaseService.instance.sendPasswordReset(email);
    setState(() {
      _isLoading = false;
      if (res.isOk) {
        _successMsg = 'Email di reset inviata a $email. Controlla la casella di posta.';
      } else {
        _errorMsg = res.failure.message;
      }
    });
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _errorMsg = null; _successMsg = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        // Su Web usa la finestra del browser, su app mobile userà un deep link
        redirectTo: kIsWeb ? null : 'io.supabase.timekeeper://login-callback',
      );
      // Nota bene: su Flutter Web il metodo signInWithOAuth reindirizza 
      // automaticamente la pagina. L'esecuzione del codice si ferma qui.
    } on AuthException catch (e) {
      if (mounted) setState(() { _errorMsg = e.message; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _errorMsg = 'Errore imprevisto: $e'; _isLoading = false; });
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── logo / titolo ────────────────────────────────────────
                const Icon(Icons.access_time_filled, size: 64, color: Colors.teal),
                const SizedBox(height: 12),
                Text(
                  'TimeKeeper',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Accedi al tuo account' : 'Crea un nuovo account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),

                // ── messaggi ─────────────────────────────────────────────
                if (_errorMsg != null) ...[
                  _MessageBanner(message: _errorMsg!, isError: true),
                  const SizedBox(height: 16),
                ],
                if (_successMsg != null) ...[
                  _MessageBanner(message: _successMsg!, isError: false),
                  const SizedBox(height: 16),
                ],

                // ── form ─────────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Inserisci la tua email.';
                          if (!v.contains('@')) return 'Email non valida.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                        obscureText: _obscurePass,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Inserisci la password.';
                          if (!_isLogin && v.length < 6) return 'Minimo 6 caratteri.';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                // ── password dimenticata ──────────────────────────────────
                if (_isLogin) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _sendPasswordReset,
                      child: const Text('Password dimenticata?', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ] else
                  const SizedBox(height: 16),

                // ── bottone principale ────────────────────────────────────
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitEmail,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isLogin ? 'Accedi' : 'Registrati'),
                ),

                const SizedBox(height: 16),

                // ── divider ───────────────────────────────────────────────
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('oppure', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ]),

                const SizedBox(height: 16),

                // ── Google Sign-In ────────────────────────────────────────
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.white),
                  label: const Text('Continua con Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),

                const SizedBox(height: 24),

                // ── switch login/registrazione ────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLogin ? 'Non hai un account?' : 'Hai già un account?',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _isLogin    = !_isLogin;
                        _errorMsg   = null;
                        _successMsg = null;
                      }),
                      child: Text(_isLogin ? 'Registrati' : 'Accedi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── banner messaggi ───────────────────────────────────────────────────────────

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : Colors.teal).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isError ? Colors.red : Colors.teal, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red : Colors.teal,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: isError ? Colors.red : Colors.teal, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}