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

  // ── public sync API ───────────────────────────────────────────────────────

  /// Full pull from Firestore into Hive. Call on app start / after login.
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

  /// Schedules a debounced push (5s). Call after every local write.
  void schedulePush() {
    if (_disabled || !isSignedIn) return;
    _hasPendingChanges = true;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _push);
  }

  /// Immediate push. Call on page navigation to flush pending changes.
  Future<void> flush() async {
    if (_disabled || !_hasPendingChanges || !isSignedIn) return;
    _debounce?.cancel();
    await _push();
  }

  // ── soft delete (tombstone) ───────────────────────────────────────────────
  //
  // IMPORTANT: never delete records directly from Hive.
  // Always use these methods so the deletion propagates to all devices.
  // The tombstone (deletedAt field) is picked up by pullAll() on every device.

  Future<void> deleteHour(int id) async {
    final box = HiveProvider.instance.hours;
    final existing = box.get(id);
    if (existing == null) return;

    final record = _cast(existing);
    final now    = DateTime.now().toIso8601String();
    record['deletedAt'] = now;
    record['updatedAt'] = now;
    await box.put(id, record);

    if (!_disabled && isSignedIn) {
      await _col('hours').doc(id.toString()).set(
        {
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<void> deleteAzienda(int id) async {
    final box = HiveProvider.instance.aziende;
    final existing = box.get(id);
    if (existing == null) return;

    final record = _cast(existing);
    final now    = DateTime.now().toIso8601String();
    record['deletedAt'] = now;
    record['updatedAt'] = now;
    await box.put(id, record);

    if (!_disabled && isSignedIn) {
      await _col('aziende').doc(id.toString()).set(
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

  // PULL: merge Firestore into Hive using Last-Write-Wins.
  //
  // Rules:
  //   - Never clears the box.
  //   - Tombstone (deletedAt != null) → delete from Hive.
  //   - Remote newer than local → overwrite Hive.
  //   - Local newer than remote → do nothing (push will handle it).
  //   - Record missing locally → write it (new from another device).

  Future<void> _pullHours() async {
    final snap = await _col('hours').get();
    final box  = HiveProvider.instance.hours;

    for (final doc in snap.docs) {
      final remote = doc.data();
      remote['id'] = int.tryParse(doc.id) ?? 0;
      final id = remote['id'] as int;

      // Tombstone: this record was deleted on another device.
      if (remote['deletedAt'] != null) {
        await box.delete(id);
        continue;
      }

      final existing = box.get(id);

      if (existing == null) {
        await box.put(id, remote);
      } else {
        final localTs  = _parseTs(existing['updatedAt']);
        final remoteTs = _parseTs(remote['updatedAt']);
        if (remoteTs != null && (localTs == null || remoteTs.isAfter(localTs))) {
          await box.put(id, remote);
        }
      }
    }
  }

  Future<void> _pullAziende() async {
    final snap = await _col('aziende').get();
    final box  = HiveProvider.instance.aziende;

    for (final doc in snap.docs) {
      final remote = doc.data();
      remote['id'] = int.tryParse(doc.id) ?? 0;
      final id = remote['id'] as int;

      if (remote['deletedAt'] != null) {
        await box.delete(id);
        continue;
      }

      final existing = box.get(id);

      if (existing == null) {
        await box.put(id, remote);
      } else {
        final localTs  = _parseTs(existing['updatedAt']);
        final remoteTs = _parseTs(remote['updatedAt']);
        if (remoteTs != null && (localTs == null || remoteTs.isAfter(localTs))) {
          await box.put(id, remote);
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
      // _hasPendingChanges stays true → retried on next schedulePush/flush
    } finally {
      _isSyncing = false;
    }
  }

  // PUSH: upsert local records to Firestore using Last-Write-Wins.
  //
  // Rules:
  //   - Fetches current Firestore state first to compare timestamps.
  //   - Only writes if local updatedAt >= remote updatedAt (or record is new).
  //   - Tombstoned local records are pushed as tombstones.
  //   - Respects Firestore 500-op batch limit.

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
      final docId    = local['id'].toString();
      final localTs  = _parseTs(local['updatedAt']);
      final remote   = remoteMap[docId];
      final remoteTs = remote != null ? _parseTs(remote['updatedAt']) : null;

      // Remote is strictly newer → skip, pull already handles it.
      if (remoteTs != null && localTs != null && remoteTs.isAfter(localTs)) {
        continue;
      }

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
      final docId    = local['id'].toString();
      final localTs  = _parseTs(local['updatedAt']);
      final remote   = remoteMap[docId];
      final remoteTs = remote != null ? _parseTs(remote['updatedAt']) : null;

      if (remoteTs != null && localTs != null && remoteTs.isAfter(localTs)) {
        continue;
      }

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

  /// Parses timestamps from DateTime, Firestore Timestamp, or ISO string.
  DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is DateTime)  return value;
    if (value is Timestamp) return value.toDate();
    if (value is String)    return DateTime.tryParse(value);
    return null;
  }
}