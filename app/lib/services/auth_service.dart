import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';

class AuthService {
  // En modo demo usamos un usuario ficticio
  static const String _demoUserId = 'demo-user-oece';
  static const String _demoName = 'Usuario Demo';
  static const String _demoEmail = 'demo@oece.gob.pe';

  FirebaseAuth? get _auth =>
      AppConfig.demoMode ? null : FirebaseAuth.instance;
  GoogleSignIn? get _googleSignIn =>
      AppConfig.demoMode ? null : GoogleSignIn();

  Future<UserCredential?> signInWithGoogle() async {
    if (AppConfig.demoMode) return null;
    try {
      final googleUser = await _googleSignIn!.signIn();
      if (googleUser == null) return null;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth!.signInWithCredential(credential);
    } catch (e) {
      throw Exception('Error al iniciar sesión con Google: $e');
    }
  }

  Future<void> signOut() async {
    if (AppConfig.demoMode) return;
    await Future.wait([_auth!.signOut(), _googleSignIn!.signOut()]);
  }

  String get userDisplayName => AppConfig.demoMode
      ? _demoName
      : (_auth?.currentUser?.displayName ??
          _auth?.currentUser?.email ??
          'Usuario');

  String? get userPhotoUrl =>
      AppConfig.demoMode ? null : _auth?.currentUser?.photoURL;

  String? get userEmail =>
      AppConfig.demoMode ? _demoEmail : _auth?.currentUser?.email;

  String get userId =>
      AppConfig.demoMode ? _demoUserId : (_auth?.currentUser?.uid ?? '');
}
