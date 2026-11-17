import 'package:firebase_auth/firebase_auth.dart';

import 'user_repository.dart';

/// Email and password authentication. Creates the profile document on sign up.
class AuthRepository {
  AuthRepository(this._auth, this._users);

  final FirebaseAuth _auth;
  final UserRepository _users;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) throw ArgumentError('Display name is required');
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(name);
    final profile = await _users.ensureProfile(
      uid: user.uid,
      email: user.email ?? email.trim(),
      displayName: name,
    );
    // The auth listener may have created the profile first with a fallback
    // name, so make sure the chosen name wins.
    if (profile.displayName != name) {
      await _users.updateProfile(user.uid, displayName: name);
    }
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _users
            .setPresence(uid, online: false)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Presence is best effort; never block sign out on it.
      }
    }
    await _auth.signOut();
  }

  /// Turns auth errors into short, plain sentences for the UI.
  static String describeError(Object error) {
    if (error is ArgumentError) return '${error.message}.';
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That email address does not look right.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return 'Email or password is incorrect.';
        case 'email-already-in-use':
          return 'An account already exists for that email.';
        case 'weak-password':
          return 'Choose a password with at least 6 characters.';
        case 'too-many-requests':
          return 'Too many attempts. Wait a moment and try again.';
        case 'network-request-failed':
          return 'No connection. Check your network and try again.';
        case 'operation-not-allowed':
          return 'Email sign-in is not enabled for this Firebase project.';
      }
      return error.message ?? 'Something went wrong. Try again.';
    }
    return 'Something went wrong. Try again.';
  }
}
