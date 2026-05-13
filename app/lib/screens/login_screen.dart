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
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential != null && mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthGate()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;
    return Scaffold(
      body: isWide ? _buildWideLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.black, Color(0xFF3A0008)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLogo(),
                    const Spacer(),
                    const Text(
                      'Consulta normativas,\nprocesos y licitaciones\ncon inteligencia artificial.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildFeatureList(),
                    const Spacer(flex: 2),
                    Text(
                      '© ${DateTime.now().year} OECE · Organismo Especializado\nen Contrataciones del Estado · Perú',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            color: const Color(0xFFF3F4F6),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: _buildLoginCard(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.black, Color(0xFF3A0008)],
        ),
      ),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                children: [
                  _buildLogo(),
                  const SizedBox(height: 32),
                  const Text(
                    'Asistente de\nContrataciones Públicas',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Consulta normativas, procesos de selección\ny todo sobre contrataciones del Estado peruano.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.65), fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 36),
                  _buildFeatureList(),
                  const SizedBox(height: 40),
                  _buildLoginCard(dark: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryRed,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppTheme.primaryRed.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: const Center(
            child: Icon(Icons.account_balance, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OECE-IA',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.silver.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.silver.withOpacity(0.5), width: 1),
              ),
              child: const Text('Contrataciones Públicas',
                  style: TextStyle(
                      color: AppTheme.silver,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureList() {
    final features = [
      (Icons.gavel_outlined, 'Ley N° 30225 y reglamento vigente'),
      (Icons.search_outlined, 'Búsqueda en documentos OECE'),
      (Icons.verified_outlined, 'Respuestas con fuentes citadas'),
      (Icons.lock_outline, 'Acceso solo con cuenta autorizada'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: features
          .map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(f.$1, color: AppTheme.silver, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Text(f.$2,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85), fontSize: 13.5)),
                ]),
              ))
          .toList(),
    );
  }

  Widget _buildLoginCard({bool dark = false}) {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.07) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? Colors.white.withOpacity(0.15) : const Color(0xFFE5E7EB),
        ),
        boxShadow: dark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Iniciar sesión',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Usa tu cuenta de Google institucional para acceder.',
            style: TextStyle(
              fontSize: 13.5,
              color: dark ? Colors.white60 : AppTheme.textGray,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                        color: dark ? Colors.white : AppTheme.primaryRed,
                        strokeWidth: 2.5))
                : _GoogleSignInButton(onTap: _signIn, dark: dark),
          ),
          const SizedBox(height: 24),
          Divider(
              color: dark
                  ? Colors.white.withOpacity(0.15)
                  : const Color(0xFFE5E7EB)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.support_agent,
                  size: 14,
                  color: dark ? Colors.white38 : AppTheme.textGray),
              const SizedBox(width: 6),
              Text(
                '¿Necesitas ayuda? WhatsApp +51 910 561 256',
                style: TextStyle(
                  fontSize: 11.5,
                  color: dark ? Colors.white38 : AppTheme.textGray,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoogleSignInButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool dark;
  const _GoogleSignInButton({required this.onTap, this.dark = false});

  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.dark
                    ? Colors.white.withOpacity(0.18)
                    : const Color(0xFFF3F4F6))
                : (widget.dark ? Colors.white.withOpacity(0.12) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.dark
                  ? Colors.white.withOpacity(0.3)
                  : const Color(0xFFD1D5DB),
              width: 1.5,
            ),
            boxShadow: _hovered && !widget.dark
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(painter: _GoogleLogoPainter()),
              ),
              const SizedBox(width: 12),
              Text(
                'Continuar con Google',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: widget.dark ? Colors.white : AppTheme.textDark,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    paint.color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r, paint);
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.7),
      -0.3, 4.8, false,
      paint..style = PaintingStyle.stroke..strokeWidth = r * 0.28,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
