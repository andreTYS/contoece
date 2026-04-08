import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const OeceIaApp());
}

class OeceIaApp extends StatelessWidget {
  const OeceIaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OECE-IA Contrataciones',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        if (snapshot.hasData && snapshot.data != null) {
          return _RoleGate(user: snapshot.data!);
        }
        return const LoginScreen();
      },
    );
  }
}

/// Después de autenticarse, crea el perfil en Firestore y redirige según el rol.
class _RoleGate extends StatefulWidget {
  final User user;
  const _RoleGate({required this.user});

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _setupUser();
  }

  Future<void> _setupUser() async {
    await _firestoreService.ensureUserProfile(
      uid: widget.user.uid,
      email: widget.user.email ?? '',
      displayName: widget.user.displayName ?? widget.user.email ?? 'Usuario',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _firestoreService.userRoleStream(widget.user.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingScreen();
        final role = snapshot.data!;
        return ChatScreen(role: role);
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.primaryBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              'OECE-IA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
