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

class _DemoEntry extends StatelessWidget {
  const _DemoEntry();

  @override
  Widget build(BuildContext context) {
    return const ChatScreen(role: 'admin');
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

class _RoleGate extends StatelessWidget {
  final User user;
  const _RoleGate({required this.user});

  @override
  Widget build(BuildContext context) {
    final email = user.email ?? '';

    if (!AppConfig.isEmailAllowed(email)) {
      return _UnauthorizedScreen(email: email);
    }

    final role = AppConfig.adminEmails.contains(email.toLowerCase())
        ? 'admin'
        : 'user';
    FirestoreService().ensureUserProfile(
      uid: user.uid,
      email: email,
      displayName: user.displayName ?? email,
    );
    return ChatScreen(role: role);
  }
}

class _UnauthorizedScreen extends StatelessWidget {
  final String email;
  const _UnauthorizedScreen({required this.email});

  Future<void> _signOut(BuildContext context) async {
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryRed,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Acceso no autorizado',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'La cuenta $email no pertenece a un dominio institucional autorizado.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Dominios permitidos: ${AppConfig.allowedDomains.join(", ")}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryRed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.primaryRed,
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
