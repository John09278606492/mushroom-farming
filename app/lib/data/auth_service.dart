import 'package:firebase_auth/firebase_auth.dart';

/// Sign-in with Firebase Auth (email + password).
///
/// Accounts are created by the admin in the Firebase console
/// (Authentication → Users → Add user), so there is no sign-up screen.
class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> watchUser() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Returns null on success, or a message the user can understand.
  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'invalid-email' => 'That email address is not valid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Wrong email or password.',
        'too-many-requests' => 'Too many tries. Wait a few minutes and try again.',
        'network-request-failed' => 'No internet connection.',
        _ => 'Sign-in failed (${e.code}).',
      };
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return e.code == 'invalid-email'
          ? 'That email address is not valid.'
          : 'Could not send the reset email (${e.code}).';
    }
  }

  Future<void> signOut() => _auth.signOut();
}
