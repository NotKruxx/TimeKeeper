// lib/core/firebase/firebase_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../database/hive_provider.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  static const _debounceDelay = Duration(seconds: 5);

  // ── test mode ─────────────────────────────────────────────────────────────
  // Call disableForTesting() in setUpAll() to prevent Firebase init in tests.
  bool _disabled = false;
  void disableForTesting() => _disabled = true;

  // ── lazy Firebase access (never touched in test mode) ─────────────────────
  FirebaseAuth?       _auth;
  FirebaseFirestore?  _firestore;

  FirebaseAuth      get _fb   => _auth      ??= FirebaseAuth.instance;
  FirebaseFirestore get _fs   => _firestore ??= FirebaseFirestore.instance;

  Timer? _debounce;
  bool   _hasPendingChanges = false;
  bool   _isSyncing         = false;

  // ── auth ──────────────────────────────────────────────────────────────────

  User?   get currentUser => _disabled ? null : _fb.currentUser;
  bool    get isSignedIn  => currentUser != null;
  String? get uid         => currentUser?.uid;

  Stream<User?> get authStateChanges =>
      _disabled ? const Stream.empty() : _fb.authStateChanges();

  Future<User?> signInWithGoogle() async {
    if (_disabled) return null;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()..addScope('email');
        final result   = await _fb.signInWithPopup(provider);
        return result.user;
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return null;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken:     googleAuth.idToken,
        );
        return (await _fb.signInWithCredential(credential)).user;
      }
    } catch (e) {
      debugPrint('[Firebase] signIn: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    if (_disabled) return;
    await flush();
    await _fb.signOut();
    if (!kIsWeb) await GoogleSignIn().signOut();
    await HiveProvider.instance.clearAll();
  }

  // ── sync ──────────────────────────────────────────────────────────────────

  Future<void> pullAll() async {
    if (_disabled || !isSignedIn) return;
    _isSyncing = true;
    try {
      await Future.wait([_pullAziende(), _pullHours()]);
    } catch (e) {
      debugPrint('[Firebase] pullAll: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Schedula un push dopo 5s di inattività.
  /// No-op in test mode.
  void schedulePush() {
    if (_disabled || !isSignedIn) return;
    _hasPendingChanges = true;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _push);
  }

  /// Push immediato — chiamato alla navigazione tra pagine.
  Future<void> flush() async {
    if (_disabled || !_hasPendingChanges || !isSignedIn) return;
    _debounce?.cancel();
    await _push();
  }

  // ── internals ─────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _fs.collection('users').doc(uid!).collection(name);

  Future<void> _pullAziende() async {
    final snap = await _col('aziende').get();
    final box  = HiveProvider.instance.aziende;
    await box.clear();
    for (final doc in snap.docs) {
      final data = doc.data();
      data['id'] = int.tryParse(doc.id) ?? 0;
      await box.put(data['id'], data);
    }
  }

  Future<void> _pullHours() async {
    final snap = await _col('hours').get();
    final box  = HiveProvider.instance.hours;
    await box.clear();
    for (final doc in snap.docs) {
      final data = doc.data();
      data['id'] = int.tryParse(doc.id) ?? 0;
      await box.put(data['id'], data);
    }
  }

  Future<void> _push() async {
    if (_isSyncing || !isSignedIn) return;
    _isSyncing = true;
    try {
      await Future.wait([_pushAziende(), _pushHours()]);
      _hasPendingChanges = false;
    } catch (e) {
      debugPrint('[Firebase] push: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pushAziende() async {
    final batch = _fs.batch();
    final col   = _col('aziende');
    for (final doc in (await col.get()).docs) {
      batch.delete(doc.reference);
    }
    for (final raw in HiveProvider.instance.aziende.values) {
      final m = _cast(raw);
      batch.set(col.doc(m['id'].toString()), m);
    }
    await batch.commit();
  }

  Future<void> _pushHours() async {
    final batch = _fs.batch();
    final col   = _col('hours');
    for (final doc in (await col.get()).docs) {
      batch.delete(doc.reference);
    }
    for (final raw in HiveProvider.instance.hours.values) {
      final m = _cast(raw);
      batch.set(col.doc(m['id'].toString()), m);
    }
    await batch.commit();
  }

  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
}
