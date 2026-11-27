import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, {GoogleSignIn? google})
    : _google = google ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _googleInitialization;

  @override
  Stream<AuthSession?> get sessions => _auth.authStateChanges().map(
    (user) =>
        user == null ? null : AuthSession(uid: user.uid, email: user.email),
  );

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _firebase(
      () => _auth.signInWithEmailAndPassword(email: email, password: password),
    );
  }

  @override
  Future<void> registerWithEmail(String email, String password) async {
    await _firebase(
      () => _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _firebase(() => _auth.sendPasswordResetEmail(email: email));
    } on AuthFailure catch (error) {
      if (error != AuthFailure.invalidCredentials) rethrow;
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _firebase(() => _auth.signInWithPopup(GoogleAuthProvider()));
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw AuthFailure.providerUnavailable;
    }

    try {
      await _initializeGoogle();
    } on GoogleSignInException {
      throw AuthFailure.providerUnavailable;
    }

    try {
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw AuthFailure.providerUnavailable;
      }
      await _firebase(
        () => _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        ),
      );
    } on GoogleSignInException catch (error) {
      throw switch (error.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted => AuthFailure.googleCanceled,
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          AuthFailure.providerUnavailable,
        _ => AuthFailure.unexpected,
      };
    }
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _initializeGoogle();
        await _google.signOut();
      } catch (_) {
        // Clearing Android's saved credential state is best-effort.
      }
    }
    await _firebase(_auth.signOut);
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure.sessionExpired;
    await _firebase(user.delete);
  }

  Future<void> _initializeGoogle() async {
    try {
      // Google Services supplies default_web_client_id from google-services.json.
      await (_googleInitialization ??= _google.initialize());
    } catch (_) {
      _googleInitialization = null;
      rethrow;
    }
  }

  @override
  Future<bool> hasDataAccess({bool refresh = false}) async {
    final result = await _currentToken(refresh);
    if (result == null) throw AuthFailure.sessionExpired;
    return result.claims?['role'] == 'authenticated';
  }

  // Supabase calls this per request. A signed-in user without the role cannot
  // silently fall back to the public role for a protected operation.
  Future<String?> accessToken() async {
    final result = await _currentToken(false);
    if (result == null) return null;
    if (result.claims?['role'] != 'authenticated') {
      throw AuthFailure.awaitingDataAccess;
    }
    return result.token;
  }

  Future<IdTokenResult?> _currentToken(bool refresh) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final result = await _firebase(() => user.getIdTokenResult(refresh));
    if (_auth.currentUser?.uid != user.uid ||
        result.claims?['sub'] != user.uid ||
        (result.token?.isEmpty ?? true)) {
      throw AuthFailure.sessionExpired;
    }
    return result;
  }

  Future<T> _firebase<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      throw switch (error.code) {
        'invalid-credential' ||
        'invalid-login-credentials' ||
        'user-not-found' ||
        'wrong-password' => AuthFailure.invalidCredentials,
        'invalid-email' => AuthFailure.invalidEmail,
        'weak-password' ||
        'password-does-not-meet-requirements' => AuthFailure.weakPassword,
        'email-already-in-use' => AuthFailure.emailAlreadyInUse,
        'user-disabled' => AuthFailure.accountDisabled,
        'network-request-failed' => AuthFailure.network,
        'too-many-requests' => AuthFailure.rateLimited,
        'popup-closed-by-user' ||
        'cancelled-popup-request' => AuthFailure.googleCanceled,
        'operation-not-allowed' ||
        'unauthorized-domain' ||
        'popup-blocked' => AuthFailure.providerUnavailable,
        'account-exists-with-different-credential' =>
          AuthFailure.emailSignInRequired,
        'user-token-expired' ||
        'invalid-user-token' ||
        'user-signed-out' => AuthFailure.sessionExpired,
        'requires-recent-login' => AuthFailure.requiresRecentLogin,
        _ => AuthFailure.unexpected,
      };
    }
  }
}
