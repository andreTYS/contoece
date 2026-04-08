import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthGate()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primaryBlue,
              AppTheme.secondaryBlue,
              Color(0xFF001F5E),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    // Logo / Escudo
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.account_balance,
                              color: AppTheme.primaryBlue,
                              size: 42,
                            ),
                            Text(
                              'OECE',
                              style: TextStyle(
                                color: AppTheme.primaryBlue,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Titulo
                    const Text(
                      'OECE-IA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.accentGold.withOpacity(0.5)),
                      ),
                      child: const Text(
                        'Asistente de Contrataciones Públicas',
                        style: TextStyle(
                          color: AppTheme.accentGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Descripcion
                    Text(
                      'Consulta normativas, procesos de selección,\nlicitaciones y todo sobre contrataciones\ndel Estado peruano.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 14.5,
                        height: 1.6,
                      ),
                    ),
                    const Spacer(flex: 2),

                    // Features
                    _buildFeatureRow(
                        Icons.search, 'Consulta en lenguaje natural'),
                    const SizedBox(height: 12),
                    _buildFeatureRow(
                        Icons.menu_book, 'Base normativa OECE actualizada'),
                    const SizedBox(height: 12),
                    _buildFeatureRow(
                        Icons.shield, 'Respuestas precisas y confiables'),
                    const Spacer(flex: 1),

                    // Boton Google
                    SizedBox(
                      width: double.infinity,
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white),
                            )
                          : ElevatedButton(
                              onPressed: _signInWithGoogle,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.textDark,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 4,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.network(
                                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                    width: 24,
                                    height: 24,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.login,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Iniciar sesión con Google',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),

                    // Footer
                    Text(
                      'Solo personal autorizado · OECE Perú',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.accentGold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.accentGold, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
