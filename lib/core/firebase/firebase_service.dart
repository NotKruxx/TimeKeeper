// lib/core/firebase/firebase_service.dart
//
// Sync strategy: Last-Write-Wins (LWW) via updatedAt + soft deletes (tombstones)
// Safe for multi-device, offline edits, slow networks, and crashes mid-push.

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

  bool _disabled = false;
  void disableForTesting() => _disabled = true;

  FirebaseAuth?      _auth;
  FirebaseFirestore? _firestore;

  FirebaseAuth      get _fb => _auth      ??= FirebaseAuth.instance;
  FirebaseFirestore get _fs => _firestore ??= FirebaseFirestore.instance;

  Timer? _debounce;
  bool   _hasPendingChanges = false;
  bool   _isSyncing         = false;

  User?   get currentUser => _disabled ? null : _fb.currentUser;
  bool    get isSignedIn  => currentUser != null;
  String? get uid         => currentUser?.uid;
  bool    get isSyncing   => _isSyncing;

  Stream<User?> get authStateChanges =>
      _disabled ? const Stream.empty() : _fb.authStateChanges();

  StreamController<void>? _updatesController;

  Stream<void> get updates {
    _updatesController ??= StreamController<void>.broadcast();
    return _updatesController!.stream;
  }

  void _notifyUpdates() {
    if (_updatesController != null && !_updatesController!.isClosed) {
      _updatesController!.add(null);
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
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

  Future<({User? user, String? error})> registerWithEmail({required String email, required String password}) async {
    if (_disabled) return (user: null, error: 'disabled');
    try {
      final result = await _fb.createUserWithEmailAndPassword(email: email.trim(), password: password);
      await result.user?.sendEmailVerification();
      return (user: result.user, error: null);
    } on FirebaseAuthException catch (e) {
      return (user: null, error: _authErrorMessage(e.code));
    } catch (e) {
      return (user: null, error: 'Errore sconosciuto');
    }
  }

  Future<({User? user, String? error})> signInWithEmail({required String email, required String password}) async {
    if (_disabled) return (user: null, error: 'disabled');
    try {
      final result = await _fb.signInWithEmailAndPassword(email: email.trim(), password: password);
      final user = result.user;
      if (user != null && !user.emailVerified) {
        await _fb.signOut();
        return (user: null, error: 'Email non verificata. Controlla la tua casella di posta.');
      }
      return (user: user, error: null);
    } on FirebaseAuthException catch (e) {
      return (user: null, error: _authErrorMessage(e.code));
    } catch (e) {
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

  Future<void> resendVerificationEmail() async => await _fb.currentUser?.sendEmailVerification();

  Future<void> signOut() async {
    if (_disabled) return;
    _isSyncing = false;
    await flush();
    await _fb.signOut();
    if (!kIsWeb) {
      try { await GoogleSignIn().signOut(); } catch (_) {}
    }
    await HiveProvider.instance.clearAll();
    _notifyUpdates();
  }

  // ── Sync API ──────────────────────────────────────────────────────────────
  Future<void> pullAll() async {
    if (_disabled || !isSignedIn || _isSyncing) return;
    
    _isSyncing = true;
    _notifyUpdates(); 
    try {
      await Future.wait([_pullAziende(), _pullHours()]);
    } catch (e, stack) {
      debugPrint('[Firebase] Error in pullAll: $e\n$stack');
    } finally {
      _isSyncing = false;
      _notifyUpdates();
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

  Future<void> deleteHour(String uuid) async {
    final box = HiveProvider.instance.hours;
    final existing = box.get(uuid);
    if (existing == null) return;

    final record = _cast(existing);
    final now = DateTime.now().toIso8601String();
    record['deletedAt'] = now;
    record['updatedAt'] = now;
    await box.put(uuid, record);

    if (!_disabled && isSignedIn) {
      await _col('hours').doc(uuid).set({
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    _notifyUpdates();
  }

  Future<void> deleteAzienda(String uuid) async {
    final box = HiveProvider.instance.aziende;
    final existing = box.get(uuid);
    if (existing == null) return;

    final record = _cast(existing);
    final now = DateTime.now().toIso8601String();
    record['deletedAt'] = now;
    record['updatedAt'] = now;
    await box.put(uuid, record);

    if (!_disabled && isSignedIn) {
      await _col('aziende').doc(uuid).set({
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    _notifyUpdates();
  }

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _fs.collection('users').doc(uid!).collection(name);

  Map<String, dynamic> _sanitizeForHive(Map<String, dynamic> map) {
    final sanitized = <String, dynamic>{};
    for (final entry in map.entries) {
      final val = entry.value;
      if (val is Timestamp) {
        sanitized[entry.key] = val.toDate().toIso8601String();
      } else if (val is DateTime) {
        sanitized[entry.key] = val.toIso8601String();
      } else if (val is FieldValue) {
        continue;
      } else {
        sanitized[entry.key] = val;
      }
    }
    return sanitized;
  }

  Future<void> _pullHours() async {
    if (!isSignedIn) return;
    final snap = await _col('hours').get();
    if (!isSignedIn) return;

    final box  = HiveProvider.instance.hours;
    final batchWrites = <String, Map<dynamic, dynamic>>{}; 
    final batchDeletes = <String>[];

    for (final doc in snap.docs) {
      try {
        final remote = _sanitizeForHive(doc.data());
        remote['uuid'] = doc.id;
        remote['updatedAt'] = _toIsoString(remote['updatedAt']);
        remote['deletedAt'] = _toIsoString(remote['deletedAt']);

        final uuid = doc.id;
        if (remote['deletedAt'] != null) {
          batchDeletes.add(uuid);
          continue;
        }

        final existing = box.get(uuid);
        if (existing == null) {
          batchWrites[uuid] = remote;
        } else {
          final localTs  = _parseTs(existing['updatedAt']);
          final remoteTs = _parseTs(remote['updatedAt']);
          if (remoteTs != null && (localTs == null || remoteTs.isAfter(localTs))) {
            batchWrites[uuid] = remote;
          }
        }
      } catch (_) {}
    }

    if (batchDeletes.isNotEmpty) await box.deleteAll(batchDeletes);
    if (batchWrites.isNotEmpty)  await box.putAll(batchWrites);
  }

  Future<void> _pullAziende() async {
    if (!isSignedIn) return;
    final snap = await _col('aziende').get();
    if (!isSignedIn) return;

    final box  = HiveProvider.instance.aziende;
    final batchWrites = <String, Map<dynamic, dynamic>>{};
    final batchDeletes = <String>[];

    for (final doc in snap.docs) {
      try {
        final remote = _sanitizeForHive(doc.data());
        remote['uuid'] = doc.id;
        remote['updatedAt'] = _toIsoString(remote['updatedAt']);
        remote['deletedAt'] = _toIsoString(remote['deletedAt']);

        final uuid = doc.id;
        if (remote['deletedAt'] != null) {
          batchDeletes.add(uuid);
          continue;
        }

        final existing = box.get(uuid);
        if (existing == null) {
          batchWrites[uuid] = remote;
        } else {
          final localTs  = _parseTs(existing['updatedAt']);
          final remoteTs = _parseTs(remote['updatedAt']);
          if (remoteTs != null && (localTs == null || remoteTs.isAfter(localTs))) {
            batchWrites[uuid] = remote;
          }
        }
      } catch (_) {}
    }

    if (batchDeletes.isNotEmpty) await box.deleteAll(batchDeletes);
    if (batchWrites.isNotEmpty)  await box.putAll(batchWrites);
  }

  Future<void> _push() async {
    if (_isSyncing || !isSignedIn) return;
    _isSyncing = true;
    try {
      await Future.wait([_pushAziende(), _pushHours()]);
      _hasPendingChanges = false;
      _notifyUpdates();
    } catch (_) {} finally {
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
      if (writes >= 490) { await batch.commit(); batch  = _fs.batch(); writes = 0; }
    }

    final box = HiveProvider.instance.hours;
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        final local    = _cast(raw as Map);
        final docId    = key.toString();
        final localTs  = _parseTs(local['updatedAt']);
        final remote   = remoteMap[docId];
        final remoteTs = remote != null ? _parseTs(remote['updatedAt']) : null;
        if (remoteTs != null && localTs != null && remoteTs.isAfter(localTs)) continue;
        final toWrite = Map<String, dynamic>.from(local);
        toWrite['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(col.doc(docId), toWrite, SetOptions(merge: true));
        writes++;
        await commitIfNeeded();
      } catch (_) {}
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
      if (writes >= 490) { await batch.commit(); batch  = _fs.batch(); writes = 0; }
    }

    final box = HiveProvider.instance.aziende;
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        final local    = _cast(raw as Map);
        final docId    = key.toString();
        final localTs  = _parseTs(local['updatedAt']);
        final remote   = remoteMap[docId];
        final remoteTs = remote != null ? _parseTs(remote['updatedAt']) : null;
        if (remoteTs != null && localTs != null && remoteTs.isAfter(localTs)) continue;
        final toWrite = Map<String, dynamic>.from(local);
        toWrite['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(col.doc(docId), toWrite, SetOptions(merge: true));
        writes++;
        await commitIfNeeded();
      } catch (_) {}
    }
    if (writes > 0) await batch.commit();
  }

  Map<String, dynamic> _cast(Map m) => m.map((k, v) => MapEntry(k.toString(), v));

  DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is DateTime)  return value;
    if (value is Timestamp) return value.toDate();
    if (value is String)    return DateTime.tryParse(value);
    if (value is int)       return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  String? _toIsoString(dynamic value) {
    final dt = _parseTs(value);
    return dt?.toIso8601String();
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