import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.demoMode) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

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
      home: AppConfig.demoMode ? const _DemoEntry() : const AuthGate(),
    );
  }
}

/// Modo demo: entra directo al chat sin login ni Firebase.
class _DemoEntry extends StatelessWidget {
  const _DemoEntry();

  @override
  Widget build(BuildContext context) {
    return const ChatScreen(role: 'admin'); // admin para ver también el panel
  }
}

/// Flujo real: espera la sesión de Firebase y asigna rol.
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

class _RoleGate extends StatefulWidget {
  final User user;
  const _RoleGate({required this.user});

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _firestoreService.ensureUserProfile(
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
        return ChatScreen(role: snapshot.data!);
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
