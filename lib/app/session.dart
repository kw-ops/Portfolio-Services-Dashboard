import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/api.dart';

/// Signed-in staff member, from `users/{uid}`.
/// role is `admin` (PSD super admin) or `provider` (owner of one portfolio).
class AppUser {
  final String uid;
  final String role;
  final String? providerId;
  final String email;
  final String displayName;

  const AppUser({
    required this.uid,
    required this.role,
    this.providerId,
    this.email = '',
    this.displayName = '',
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      role: m['role'] as String? ?? '',
      providerId: m['providerId'] as String?,
      email: m['email'] as String? ?? '',
      displayName: m['displayName'] as String? ?? '',
    );
  }
}

/// Tracks the signed-in admin/provider. Anonymous sessions (students
/// submitting a request) count as signed out.
class Session extends ChangeNotifier {
  Session() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
  }

  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  User? user;
  AppUser? profile;
  bool _loaded = false;
  bool _googleBusy = false;

  /// Last error from the Google admin sign-in, shown on the login page.
  String? googleError;

  /// False while auth/profile are loading or a Google admin sign-in is in
  /// progress, so gated pages show a spinner instead of flashing "no access".
  bool get ready => _loaded && !_googleBusy;

  bool get signedIn => user != null && !user!.isAnonymous;
  bool get isAdmin => profile?.role == 'admin';
  bool get isProvider => profile?.role == 'provider' && profile?.providerId != null;

  void _onAuth(User? u) {
    _profileSub?.cancel();
    user = u;
    profile = null;
    if (u == null || u.isAnonymous) {
      _loaded = true;
      notifyListeners();
      return;
    }
    _loaded = false;
    notifyListeners();
    _profileSub = FirebaseFirestore.instance.doc('users/${u.uid}').snapshots().listen(
      (d) {
        profile = d.exists ? AppUser.fromDoc(d) : null;
        _loaded = true;
        notifyListeners();
      },
      onError: (_) {
        profile = null;
        _loaded = true;
        notifyListeners();
      },
    );
  }

  Future<void> signIn(String email, String password) =>
      FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim(), password: password);

  /// Admin sign-in with Google. The very first time, this claims the admin
  /// role (only for the ADMIN_EMAIL set on the backend); afterwards it is a
  /// normal sign-in. Any other Google account is signed straight back out.
  Future<void> signInWithGoogle() async {
    _googleBusy = true;
    googleError = null;
    notifyListeners();
    try {
      final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      final ref = FirebaseFirestore.instance.doc('users/${cred.user!.uid}');
      var doc = await ref.get();
      if (!doc.exists) {
        await Api.claimAdmin();
        doc = await ref.get();
      }
      profile = doc.exists ? AppUser.fromDoc(doc) : null;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request') {
        googleError = friendlyError(e);
      }
    } catch (e) {
      googleError = friendlyError(e);
      await FirebaseAuth.instance.signOut();
    } finally {
      _googleBusy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

  @override
  void dispose() {
    _authSub.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}

late final Session session;
