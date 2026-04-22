import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../models/case_model.dart';
import '../models/message_model.dart';
import '../screens/admin_screen.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import 'login_screen.dart';

class ChatScreen extends StatefulWidget {
  final String role;
  const ChatScreen({super.key, required this.role});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final FirestoreService _firestoreService = FirestoreService();
  final AdminService _adminService = AdminService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ChatMessage> _messages = [];
  List<DocumentInfo> _sources = [];
  List<CaseModel> _cases = [];
  bool _isLoading = false;
  bool _serverConnected = false;
  bool _historyLoaded = false;
  bool _casesLoaded = false;
  String? _activeCaseId;
  String? _activeCaseName;
  StreamSubscription<List<CaseModel>>? _casesSub;

  bool get _isAdmin => widget.role == 'admin';
  String get _uid => _authService.userId;

  static const _suggested = [
    '¿Cuáles son los tipos de procedimientos de selección?',
    '¿Qué es el SEACE y cómo funciona?',
    '¿Requisitos para ser proveedor del Estado?',
    '¿Qué dice la Ley N° 30225 sobre contrataciones directas?',
    '¿Cómo se calcula el valor referencial?',
    '¿Causales de descalificación de un postor?',
  ];

  @override
  void initState() {
    super.initState();
    _checkServer();
    _loadSources();
    _subscribeToCases();
    _loadHistory();
  }

  @override
  void dispose() {
    _casesSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ─── Cases stream ─────────────────────────────────────────────────────────

  void _subscribeToCases() {
    _casesSub = _firestoreService.casesStream(_uid).listen((cases) {
      if (mounted) setState(() { _cases = cases; _casesLoaded = true; });
    }, onError: (_) {
      if (mounted) setState(() => _casesLoaded = true);
    });
  }

  // ─── History / case switching ─────────────────────────────────────────────

  Future<void> _loadHistory({String? caseId}) async {
    if (mounted && _historyLoaded) {
      setState(() { _historyLoaded = false; _messages = []; });
    }
    List<ChatMessage> history;
    if (caseId != null && caseId.isNotEmpty) {
      history = await _firestoreService.loadCaseHistory(_uid, caseId);
    } else {
      history = await _firestoreService.loadHistory(_uid);
    }
    if (mounted) {
      setState(() {
        _historyLoaded = true;
        if (history.isEmpty) { _messages = []; _addWelcome(); }
        else _messages = history;
      });
      _scrollToBottom();
    }
  }

  void _addWelcome() {
    _messages.add(ChatMessage(
      id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
      content: _activeCaseId != null
          ? 'Caso **$_activeCaseName** listo.\n\n'
            'Escribe tu consulta sobre contrataciones públicas.'
          : 'Hola, soy **OECE-IA**, tu asistente especializado en contrataciones '
            'públicas del Estado peruano.\n\n'
            'Selecciona un caso en el panel izquierdo o escribe tu consulta.',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    ));
  }

  void _selectCase(CaseModel c) async {
    if (_activeCaseId == c.id) return;
    setState(() { _activeCaseId = c.id; _activeCaseName = c.name; });
    await _loadHistory(caseId: c.id);
  }

  void _selectGeneral() async {
    if (_activeCaseId == null) return;
    setState(() { _activeCaseId = null; _activeCaseName = null; });
    await _loadHistory();
  }

  // ─── Case CRUD ────────────────────────────────────────────────────────────

  Future<void> _createCase() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nuevo caso'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej: Licitación pública LP-001',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final caseId = await _firestoreService.createCase(_uid, name);
      final newCase = CaseModel(id: caseId, name: name, createdAt: DateTime.now());
      _selectCase(newCase);
    }
  }

  Future<void> _renameCase(CaseModel c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Renombrar caso'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != c.name) {
      await _firestoreService.renameCase(_uid, c.id, name);
      if (_activeCaseId == c.id) setState(() => _activeCaseName = name);
    }
  }

  Future<void> _deleteCase(CaseModel c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar caso'),
        content: Text('Se eliminará "${c.name}" y todo su historial. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _firestoreService.deleteCase(_uid, c.id);
      if (_activeCaseId == c.id) {
        setState(() { _activeCaseId = null; _activeCaseName = null; });
        await _loadHistory();
      }
    }
  }

  // ─── Chat send ────────────────────────────────────────────────────────────

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty || _isLoading) return;
    _inputController.clear();
    _inputFocus.unfocus();

    final uid = _uid;
    final cid = _activeCaseId;
    final userMsg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      content: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );
    final loading = ChatMessage(
      id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(loading);
      _isLoading = true;
    });
    _scrollToBottom();

    if (cid != null && cid.isNotEmpty) {
      try { await _firestoreService.saveCaseMessage(uid, cid, userMsg); } catch (_) {}
    } else {
      try { await _firestoreService.saveMessage(uid, userMsg); } catch (_) {}
    }

    try {
      final history = _messages
          .where((m) => !m.isLoading && !m.id.startsWith('welcome'))
          .toList();
      final res = await _chatService.sendMessage(
        message: text,
        userId: uid,
        history: history,
        caseId: cid ?? '',
      );
      final aiMsg = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        content: res.response,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        sources: res.sources,
      );
      setState(() {
        _messages.remove(loading);
        _messages.add(aiMsg);
        _isLoading = false;
        _serverConnected = true;
      });
      if (cid != null && cid.isNotEmpty) {
        try { await _firestoreService.saveCaseMessage(uid, cid, aiMsg); } catch (_) {}
      } else {
        try { await _firestoreService.saveMessage(uid, aiMsg); } catch (_) {}
      }
      if (res.sources.isNotEmpty) _loadSources();
    } catch (e) {
      setState(() {
        _messages.remove(loading);
        _messages.add(ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          content: '**Error al conectar con el servidor.**\n\n'
              '${e.toString().replaceFirst('Exception: ', '')}',
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
        _serverConnected = false;
      });
    }
    _scrollToBottom();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _loadSources() async {
    try {
      final docs = await _adminService.listDocuments();
      if (mounted) setState(() => _sources = docs);
    } catch (_) {}
  }

  Future<void> _checkServer() async {
    final ok = await _chatService.checkServerHealth();
    if (mounted) setState(() => _serverConnected = ok);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Limpiar historial'),
        content: Text(_activeCaseId != null
            ? 'Se borrarán los mensajes de este caso. ¿Continuar?'
            : 'Se borrarán todos los mensajes. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (_activeCaseId != null) {
        await _firestoreService.clearCaseHistory(_uid, _activeCaseId!);
      } else {
        await _firestoreService.clearHistory(_uid);
      }
      setState(() { _messages.clear(); _addWelcome(); });
    }
  }

  Future<void> _signOut() async {
    if (AppConfig.demoMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Modo demo activo — login desactivado.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas salir de tu cuenta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }

  void _showSourcesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SourcesSheet(sources: _sources, isAdmin: _isAdmin),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w > 1100;
    final isMobile = w <= 640;

    if (isMobile) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF0F4F9),
        drawer: _buildCasesDrawer(),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(isMobile: true),
              if (!_serverConnected) _buildBanner(),
              Expanded(child: _buildChat()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF0F4F9),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            if (!_serverConnected) _buildBanner(),
            Expanded(
              child: Row(
                children: [
                  _buildCasesSidebar(wide: isDesktop),
                  Expanded(child: _buildChat()),
                  if (isDesktop && _sources.isNotEmpty) _buildSourcesPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar({bool isMobile = false}) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9ECF0))),
      ),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: AppTheme.primaryBlue, size: 22),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Mis casos',
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('OECE-IA',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _activeCaseName != null
                ? Row(children: [
                    const Icon(Icons.folder_open, color: AppTheme.primaryBlue, size: 15),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(_activeCaseName!,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ])
                : const Text('Asistente de Contrataciones Públicas',
                    style: TextStyle(color: AppTheme.textGray, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
          ),
          if (isMobile && _sources.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_sources.length}'),
                child: const Icon(Icons.folder_open_outlined,
                    color: AppTheme.primaryBlue, size: 22),
              ),
              onPressed: _showSourcesModal,
              tooltip: 'Ver fuentes',
            ),
          IconButton(
            icon: const Icon(Icons.support_agent,
                color: Color(0xFF25D366), size: 22),
            tooltip: 'Soporte WhatsApp',
            onPressed: _openWhatsApp,
          ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.tune, color: AppTheme.primaryBlue, size: 22),
              tooltip: 'Panel admin',
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminScreen()));
                _loadSources();
              },
            ),
          _buildAvatarMenu(),
        ],
      ),
    );
  }

  Widget _buildAvatarMenu() {
    final name = _authService.userDisplayName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final photoUrl = _authService.userPhotoUrl;

    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'logout') _signOut();
        if (v == 'clear') _clearChat();
        if (v == 'admin') Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AdminScreen()));
      },
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: AppTheme.primaryBlue,
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null
              ? Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold))
              : null,
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(_authService.userEmail ?? '',
                style: const TextStyle(color: AppTheme.textGray, fontSize: 11)),
            if (_isAdmin) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Administrador',
                    style: TextStyle(
                        color: AppTheme.accentGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ]
          ]),
        ),
        const PopupMenuDivider(),
        if (_isAdmin)
          const PopupMenuItem(
              value: 'admin',
              child: Row(children: [
                Icon(Icons.tune, size: 16, color: AppTheme.accentGold),
                SizedBox(width: 10),
                Text('Panel admin'),
              ])),
        const PopupMenuItem(
            value: 'clear',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: AppTheme.textGray),
              SizedBox(width: 10),
              Text('Limpiar historial'),
            ])),
        const PopupMenuItem(
            value: 'logout',
            child: Row(children: [
              Icon(Icons.logout, size: 16, color: Colors.red),
              SizedBox(width: 10),
              Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
            ])),
      ],
    );
  }

  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent(AppConfig.whatsappMessage);
    final uri = Uri.parse('https://wa.me/${AppConfig.whatsappNumber}?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── Banner servidor ──────────────────────────────────────────────────────

  Widget _buildBanner() {
    return Container(
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Servidor temporalmente no disponible. Intenta en unos momentos.',
            style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: _checkServer,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: const Size(60, 28)),
          child: Text('Reintentar',
              style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
      ]),
    );
  }

  // ─── Cases sidebar (desktop/tablet) ──────────────────────────────────────

  Widget _buildCasesSidebar({required bool wide}) {
    return Container(
      width: wide ? 240 : 200,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(right: BorderSide(color: Color(0xFF334155))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              const Icon(Icons.work_outline, color: Colors.white70, size: 15),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Mis casos',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              GestureDetector(
                onTap: _createCase,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 14),
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          Expanded(child: _buildCasesList(onTap: _selectCase)),
          const Divider(height: 1, color: Color(0xFF334155)),
          InkWell(
            onTap: _createCase,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: const [
                Icon(Icons.add_circle_outline, color: Colors.white38, size: 15),
                SizedBox(width: 8),
                Text('Nuevo caso',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCasesList({VoidCallback? onAfterTap, required Function(CaseModel) onTap}) {
    if (!_casesLoaded) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      children: [
        _buildCaseTile(
          id: null,
          name: 'General',
          icon: Icons.chat_bubble_outline,
          isSelected: _activeCaseId == null,
          onTap: () { onAfterTap?.call(); _selectGeneral(); },
        ),
        if (_cases.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Text('CASOS',
                style: TextStyle(
                    color: Colors.white30,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ),
          ..._cases.map((c) => _buildCaseTile(
                id: c.id,
                name: c.name,
                icon: Icons.folder_outlined,
                isSelected: _activeCaseId == c.id,
                onTap: () { onAfterTap?.call(); onTap(c); },
                onRename: () => _renameCase(c),
                onDelete: () => _deleteCase(c),
              )),
        ] else ...[
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Crea un caso para organizar tus consultas por expediente.',
              style: TextStyle(color: Colors.white30, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCaseTile({
    required String? id,
    required String name,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onRename,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryBlue.withOpacity(0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 8, right: 4),
        leading: Icon(icon,
            color: isSelected ? Colors.white : Colors.white54, size: 16),
        title: Text(
          name,
          style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 12.5,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
        trailing: (onRename != null || onDelete != null)
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz,
                    color: Colors.white30, size: 16),
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'rename') onRename?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onRename != null)
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 14),
                        SizedBox(width: 8),
                        Text('Renombrar', style: TextStyle(fontSize: 13)),
                      ]),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 14, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Eliminar',
                            style:
                                TextStyle(fontSize: 13, color: Colors.red)),
                      ]),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildCasesDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1E293B),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('OECE-IA',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _createCase();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nuevo caso'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF334155)),
            Expanded(
              child: _buildCasesList(
                onAfterTap: () => Navigator.pop(context),
                onTap: _selectCase,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sources panel (right, desktop) ──────────────────────────────────────

  Widget _buildSourcesPanel() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE9ECF0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(children: [
              const Icon(Icons.folder_open_outlined,
                  color: AppTheme.primaryBlue, size: 15),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Fuentes',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.textDark)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_sources.length}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              itemCount: _sources.length,
              itemBuilder: (_, i) => _buildSourceCard(_sources[i]),
            ),
          ),
          if (_isAdmin) ...[
            const Divider(height: 1),
            _buildAddSourceBtn(),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceCard(DocumentInfo doc) {
    final ext = doc.source.split('.').last.toUpperCase();
    final color = ext == 'PDF'
        ? Colors.red.shade600
        : ext == 'DOCX'
            ? Colors.blue.shade600
            : Colors.green.shade600;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE9ECF0)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(ext,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            doc.source.replaceAll(RegExp(r'\.\w+$'), ''),
            style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _buildAddSourceBtn() {
    return InkWell(
      onTap: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminScreen()));
        _loadSources();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: const [
          Icon(Icons.add_circle_outline,
              color: AppTheme.primaryBlue, size: 14),
          SizedBox(width: 6),
          Text('Agregar fuente',
              style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ─── Chat area ────────────────────────────────────────────────────────────

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: !_historyLoaded
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primaryBlue, strokeWidth: 2))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 4),
                  itemCount:
                      _messages.length + (_messages.length == 1 ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_messages.length == 1 && i == 1) {
                      return _buildSuggestions();
                    }
                    return ChatBubble(message: _messages[i]);
                  },
                ),
        ),
        _buildInput(),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 10),
            child: Text('Preguntas frecuentes',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textGray,
                    letterSpacing: 0.5)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggested
                .map((q) => GestureDetector(
                      onTap: () => _send(q),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFD1D5DB)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4)
                          ],
                        ),
                        child: Text(q,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.primaryBlue)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE9ECF0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE0E4EA)),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                    fontSize: 14.5, color: AppTheme.textDark),
                decoration: InputDecoration(
                  hintText: _activeCaseName != null
                      ? 'Consulta para: $_activeCaseName...'
                      : 'Escribe tu consulta sobre contrataciones...',
                  hintStyle: const TextStyle(
                      color: AppTheme.textGray, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isLoading ? null : _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _isLoading
                    ? const Color(0xFFCBD5E1)
                    : AppTheme.primaryBlue,
                shape: BoxShape.circle,
                boxShadow: _isLoading
                    ? []
                    : [
                        BoxShadow(
                            color:
                                AppTheme.primaryBlue.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sources bottom sheet (móvil) ─────────────────────────────────────────────

class _SourcesSheet extends StatelessWidget {
  final List<DocumentInfo> sources;
  final bool isAdmin;
  const _SourcesSheet({required this.sources, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.folder_open_outlined,
                color: AppTheme.primaryBlue, size: 20),
            const SizedBox(width: 8),
            const Text('Fuentes OECE',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20)),
          ]),
          const SizedBox(height: 12),
          if (sources.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Sin documentos cargados.',
                  style: TextStyle(color: AppTheme.textGray)),
            )
          else
            ...sources.map((doc) {
              final ext = doc.source.split('.').last.toUpperCase();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(ext,
                      style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(
                    doc.source.replaceAll(RegExp(r'\.\w+$'), ''),
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text('${doc.chunks} fragmentos',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textGray)),
              );
            }),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminScreen()));
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Gestionar documentos'),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
