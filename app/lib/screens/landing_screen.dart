import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const Color _blue = Color(0xFF1A4B8C);
  static const Color _red = Color(0xFFC8102E);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      backgroundColor: Colors.white,
      body: isWide ? _buildWide() : _buildMobile(),
    );
  }

  // ─── Wide ─────────────────────────────────────────────────────────────────

  Widget _buildWide() {
    return Column(
      children: [
        _buildNav(),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: 6, child: _buildHero(wide: true)),
              Expanded(flex: 5, child: _buildFeaturesPanel()),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  // ─── Mobile ───────────────────────────────────────────────────────────────

  Widget _buildMobile() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildNav(),
          _buildHero(wide: false),
          _buildFeaturesMobile(),
          _buildFooter(),
        ],
      ),
    );
  }

  // ─── Nav bar ──────────────────────────────────────────────────────────────

  Widget _buildNav() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primaryRed,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('OECE-IA',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppTheme.black,
                  letterSpacing: 1.5)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('BETA',
                style: TextStyle(
                    color: _blue,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
          const Spacer(),
          TextButton(
            onPressed: _goToLogin,
            child: const Text('Iniciar sesión',
                style: TextStyle(
                    color: AppTheme.primaryRed, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _goToLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Acceder',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─── Hero section ─────────────────────────────────────────────────────────

  Widget _buildHero({required bool wide}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.black,
            _blue.withOpacity(0.92),
            AppTheme.primaryRed.withOpacity(0.85),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: EdgeInsets.all(wide ? 52 : 28)
                  .copyWith(top: wide ? 48 : 36, bottom: wide ? 48 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: wide
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  // Flag accent + label
                  Row(children: [
                    Container(width: 5, height: 22, color: _red),
                    Container(width: 5, height: 22, color: Colors.white),
                    Container(width: 5, height: 22, color: _red),
                    const SizedBox(width: 12),
                    Text('PERÚ · SISTEMA OFICIAL DE CONTRATACIONES',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 10,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w600)),
                  ]),
                  SizedBox(height: wide ? 28 : 20),
                  Text(
                    'Contrataciones\nPúblicas con IA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: wide ? 46 : 34,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Consulta la Ley N° 30225, directivas OECE y\nprocesos de selección con inteligencia artificial.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: wide ? 15.5 : 14,
                      height: 1.65,
                    ),
                  ),
                  SizedBox(height: wide ? 36 : 24),
                  // Stats row
                  Row(children: [
                    _buildStat('30225', 'Ley de\nContrataciones'),
                    const SizedBox(width: 28),
                    _buildStat('SEACE', 'Sistema\nintegrado'),
                    const SizedBox(width: 28),
                    _buildStat('24/7', 'Siempre\ndisponible'),
                  ]),
                  SizedBox(height: wide ? 40 : 28),
                  // CTA buttons
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _goToLogin,
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('Ingresar al sistema',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _goToLogin,
                        icon: const Icon(Icons.info_outline_rounded, size: 18),
                        label: const Text('Conoce más',
                            style: TextStyle(fontSize: 15)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.35), width: 1.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          style: const TextStyle(
              color: AppTheme.primaryRed,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5)),
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
              height: 1.4,
              fontWeight: FontWeight.w500)),
    ]);
  }

  // ─── Features panel (desktop right) ───────────────────────────────────────

  Widget _buildFeaturesPanel() {
    final features = [
      (Icons.gavel_outlined, _blue, 'Ley N° 30225 y reglamento',
          'Consulta la normativa vigente y sus modificaciones.'),
      (Icons.search_outlined, AppTheme.primaryRed, 'Búsqueda en OECE',
          'Documentos, directivas y comunicados oficiales.'),
      (Icons.verified_user_outlined, const Color(0xFF16A34A),
          'Respuestas con fuentes', 'Referencias verificables en cada respuesta.'),
      (Icons.folder_outlined, AppTheme.black, 'Gestión por casos',
          'Organiza tus consultas por expediente o proceso.'),
      (Icons.upload_file_outlined, _red, 'Tus documentos propios',
          'Sube PDFs y analízalos con la base OECE.'),
      (Icons.lock_outline, const Color(0xFF6B21A8), 'Acceso institucional',
          'Solo cuentas de correo autorizadas.'),
    ];

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Capacidades del sistema',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  color: AppTheme.black)),
          const SizedBox(height: 4),
          const Text('Herramientas para profesionales de contrataciones',
              style: TextStyle(color: AppTheme.textGray, fontSize: 13)),
          const SizedBox(height: 24),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: f.$2.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(f.$1, color: f.$2, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.$3,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AppTheme.textDark)),
                        Text(f.$4,
                            style: const TextStyle(
                                color: AppTheme.textGray,
                                fontSize: 12,
                                height: 1.35)),
                      ],
                    ),
                  ),
                ]),
              )),
        ],
      ),
    );
  }

  // ─── Features grid (mobile) ───────────────────────────────────────────────

  Widget _buildFeaturesMobile() {
    final features = [
      (Icons.gavel_outlined, _blue, 'Ley N° 30225', 'Normativa vigente'),
      (Icons.search_outlined, AppTheme.primaryRed, 'Búsqueda OECE', 'Documentos oficiales'),
      (Icons.verified_user_outlined, const Color(0xFF16A34A), 'Con fuentes', 'Referencias verificadas'),
      (Icons.folder_outlined, AppTheme.black, 'Por casos', 'Organiza expedientes'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Qué puedes hacer?',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppTheme.black)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.55,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: features.map((f) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: f.$2.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: f.$2.withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(f.$1, color: f.$2, size: 22),
                      const SizedBox(height: 8),
                      Text(f.$3,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                      Text(f.$4,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textGray),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                )).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      color: AppTheme.black,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Text(
            '© ${DateTime.now().year} OECE-IA · Contrataciones del Estado · Perú',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
          const Spacer(),
          Row(children: [
            Container(width: 4, height: 14, color: _red),
            Container(width: 4, height: 14, color: Colors.white.withOpacity(0.7)),
            Container(width: 4, height: 14, color: _red),
          ]),
        ],
      ),
    );
  }
}
