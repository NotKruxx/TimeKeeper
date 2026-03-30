// lib/core/firebase/firebase_service.dart
//
// Sync strategy: Last-Write-Wins (LWW) via updatedAt + soft deletes (tombstones)
// Safe for multi-device, offline edits, slow networks, and crashes mid-push.
//
// Auth: Google Sign-In + Email/Password con email verification.

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
  bool _disabled = false;
  void disableForTesting() => _disabled = true;

  // ── lazy Firebase access ──────────────────────────────────────────────────
  FirebaseAuth?      _auth;
  FirebaseFirestore? _firestore;

  FirebaseAuth      get _fb => _auth      ??= FirebaseAuth.instance;
  FirebaseFirestore get _fs => _firestore ??= FirebaseFirestore.instance;

  Timer? _debounce;
  bool   _hasPendingChanges = false;
  bool   _isSyncing         = false;

  // ── auth ──────────────────────────────────────────────────────────────────
  User?   get currentUser => _disabled ? null : _fb.currentUser;
  bool    get isSignedIn  => currentUser != null;
  String? get uid         => currentUser?.uid;

  Stream<User?> get authStateChanges =>
      _disabled ? const Stream.empty() : _fb.authStateChanges();

  // ── Google Sign-In ────────────────────────────────────────────────────────
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
      debugPrint('[Firebase] signInWithGoogle: $e');
      return null;
    }
  }

  // ── Email + Password ──────────────────────────────────────────────────────
  Future<({User? user, String? error})> registerWithEmail({
    required String email,
    required String password,
  }) async {
    if (_disabled) return (user: null, error: 'disabled');
    try {
      final result = await _fb.createUserWithEmailAndPassword(
        email:    email.trim(),
        password: password,
      );
      await result.user?.sendEmailVerification();
      return (user: result.user, error: null);
    } on FirebaseAuthException catch (e) {
      return (user: null, error: _authErrorMessage(e.code));
    } catch (e) {
      debugPrint('[Firebase] registerWithEmail: $e');
      return (user: null, error: 'Errore sconosciuto');
    }
  }

  Future<({User? user, String? error})> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (_disabled) return (user: null, error: 'disabled');
    try {
      final result = await _fb.signInWithEmailAndPassword(
        email:    email.trim(),
        password: password,
      );
      final user = result.user;
      if (user != null && !user.emailVerified) {
        await _fb.signOut();
        return (
          user: null,
          error: 'Email non verificata. Controlla la tua casella di posta.',
        );
      }
      return (user: user, error: null);
    } on FirebaseAuthException catch (e) {
      return (user: null, error: _authErrorMessage(e.code));
    } catch (e) {
      debugPrint('[Firebase] signInWithEmail: $e');
      return (user: null, error: 'Errore sconosciuto');
    }
  }

  Future<({bool success, String? error})> sendPasswordReset(String email) async {
    if (_disabled) return (success: false, error: 'disabled');
    try {
      await _fb.sendPasswordResetEmail(email: email.trim());
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _authErrorMessage(e.code));
    } catch (e) {
      return (success: false, error: 'Errore sconosciuto');
    }
  }

  Future<void> resendVerificationEmail() async {
    await _fb.currentUser?.sendEmailVerification();
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    if (_disabled) return;
    await flush();
    await _fb.signOut();
    if (!kIsWeb) {
      try { await GoogleSignIn().signOut(); } catch (_) {}
    }
    await HiveProvider.instance.clearAll();
  }

  // ── public sync API ───────────────────────────────────────────────────────
  Future<void> pullAll() async {
    print("📥 pullAll chiamato");
    print("isSignedIn: $isSignedIn");
    print("uid: $uid");

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

  void schedulePush() {
    if (_disabled || !isSignedIn) return;
    _hasPendingChanges = true;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _push);
  }

  Future<void> flush() async {
    if (_disabled || !_hasPendingChanges || !isSignedIn) return;
    _debounce?.cancel();
    await _push();
  }

  // ── soft delete (tombstone) ───────────────────────────────────────────────
  Future<void> deleteHour(String uuid) async {
    final box      = HiveProvider.instance.hours;
    final existing = box.get(uuid);
    if (existing == null) return;

    final record = _cast(existing);
    final now    = DateTime.now().toIso8601String();
    record['deletedAt'] = now;
    record['updatedAt'] = now;
    await box.put(uuid, record);

    if (!_disabled && isSignedIn) {
      await _col('hours').doc(uuid).set(
        {
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<void> deleteAzienda(String uuid) async {
    final box      = HiveProvider.instance.aziende;
    final existing = box.get(uuid);
    if (existing == null) return;

    final record = _cast(existing);
    final now    = DateTime.now().toIso8601String();
    record['deletedAt'] = now;
    record['updatedAt'] = now;
    await box.put(uuid, record);

    if (!_disabled && isSignedIn) {
      await _col('aziende').doc(uuid).set(
        {
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  // ── internals ─────────────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _fs.collection('users').doc(uid!).collection(name);

  Future<void> _pullHours() async {
    final snap = await _col('hours').get();
    final box  = HiveProvider.instance.hours;

    for (final doc in snap.docs) {
      final remote = doc.data();
      remote['uuid'] = doc.id;

      // Normalize Timestamp -> ISO string
      remote.forEach((k, v) {
        if (v is Timestamp) remote[k] = v.toDate().toIso8601String();
      });

      print('[DEBUG pullHours] doc: ${doc.id}, data: $remote');

      final uuid = doc.id;
      if (remote['deletedAt'] != null) {
        await box.delete(uuid);
        continue;
      }

      final existing = box.get(uuid);
      if (existing == null) {
        await box.put(uuid, remote);
      } else {
        final localTs  = _parseTs(existing['updatedAt']);
        final remoteTs = _parseTs(remote['updatedAt']);
        if (remoteTs != null && (localTs == null || remoteTs.isAfter(localTs))) {
          await box.put(uuid, remote);
        }
      }
    }
  }

  Future<void> _pullAziende() async {
    final snap = await _col('aziende').get();
    final box  = HiveProvider.instance.aziende;

    for (final doc in snap.docs) {
      final remote = doc.data();
      remote['uuid'] = doc.id;

      // Normalize Timestamp -> ISO string
      remote.forEach((k, v) {
        if (v is Timestamp) remote[k] = v.toDate().toIso8601String();
      });

      print('[DEBUG pullAziende] doc: ${doc.id}, data: $remote');

      final uuid = doc.id;
      if (remote['deletedAt'] != null) {
        await box.delete(uuid);
        continue;
      }

      final existing = box.get(uuid);
      if (existing == null) {
        await box.put(uuid, remote);
      } else {
        final localTs  = _parseTs(existing['updatedAt']);
        final remoteTs = _parseTs(remote['updatedAt']);
        if (remoteTs != null && (localTs == null || remoteTs.isAfter(localTs))) {
          await box.put(uuid, remote);
        }
      }
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

  Future<void> _pushHours() async {
    final col       = _col('hours');
    final snap      = await col.get();
    final remoteMap = {for (final d in snap.docs) d.id: d.data()};

    var batch  = _fs.batch();
    var writes = 0;

    Future<void> commitIfNeeded() async {
      if (writes >= 490) {
        await batch.commit();
        batch  = _fs.batch();
        writes = 0;
      }
    }

    for (final raw in HiveProvider.instance.hours.values) {
      final local    = _cast(raw);
      final docId    = local['uuid'] as String?;
      if (docId == null) continue;

      final localTs  = _parseTs(local['updatedAt']);
      final remote   = remoteMap[docId];
      final remoteTs = remote != null ? _parseTs(remote['updatedAt']) : null;

      if (remoteTs != null && localTs != null && remoteTs.isAfter(localTs)) continue;

      final toWrite = Map<String, dynamic>.from(local);
      toWrite['updatedAt'] = FieldValue.serverTimestamp();

      batch.set(col.doc(docId), toWrite, SetOptions(merge: true));
      writes++;
      await commitIfNeeded();
    }

    if (writes > 0) await batch.commit();
  }

  Future<void> _pushAziende() async {
    final col       = _col('aziende');
    final snap      = await col.get();
    final remoteMap = {for (final d in snap.docs) d.id: d.data()};

    var batch  = _fs.batch();
    var writes = 0;

    Future<void> commitIfNeeded() async {
      if (writes >= 490) {
        await batch.commit();
        batch  = _fs.batch();
        writes = 0;
      }
    }

    for (final raw in HiveProvider.instance.aziende.values) {
      final local    = _cast(raw);
      final docId    = local['uuid'] as String?;
      if (docId == null) continue;

      final localTs  = _parseTs(local['updatedAt']);
      final remote   = remoteMap[docId];
      final remoteTs = remote != null ? _parseTs(remote['updatedAt']) : null;

      if (remoteTs != null && localTs != null && remoteTs.isAfter(localTs)) continue;

      final toWrite = Map<String, dynamic>.from(local);
      toWrite['updatedAt'] = FieldValue.serverTimestamp();

      batch.set(col.doc(docId), toWrite, SetOptions(merge: true));
      writes++;
      await commitIfNeeded();
    }

    if (writes > 0) await batch.commit();
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  Map<String, dynamic> _cast(Map m) =>
      m.map((k, v) => MapEntry(k.toString(), v));

  DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is DateTime)  return value;
    if (value is Timestamp) return value.toDate();
    if (value is String)    return DateTime.tryParse(value);
    return null;
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':    return 'Email già in uso.';
      case 'invalid-email':           return 'Email non valida.';
      case 'weak-password':           return 'Password troppo debole (min. 6 caratteri).';
      case 'user-not-found':          return 'Nessun account trovato con questa email.';
      case 'wrong-password':          return 'Password errata.';
      case 'user-disabled':           return 'Account disabilitato.';
      case 'too-many-requests':       return 'Troppi tentativi. Riprova tra qualche minuto.';
      case 'network-request-failed':  return 'Errore di rete. Controlla la connessione.';
      case 'invalid-credential':      return 'Credenziali non valide.';
      default:                        return 'Errore: $code';
    }
  }
}