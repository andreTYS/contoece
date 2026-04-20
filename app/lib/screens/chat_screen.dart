import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
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

  List<ChatMessage> _messages = [];
  List<DocumentInfo> _sources = [];
  bool _isLoading = false;
  bool _serverConnected = false;
  bool _historyLoaded = false;

  bool get _isAdmin => widget.role == 'admin';

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
    _loadHistory();
    _loadSources();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    try {
      final docs = await _adminService.listDocuments();
      if (mounted) setState(() => _sources = docs);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final history = await _firestoreService.loadHistory(_authService.userId);
    if (mounted) {
      setState(() {
        _historyLoaded = true;
        if (history.isEmpty) _addWelcome();
        else _messages = history;
      });
      _scrollToBottom();
    }
  }

  void _addWelcome() {
    _messages.add(ChatMessage(
      id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
      content:
          'Hola, soy **OECE-IA**, tu asistente especializado en contrataciones '
          'públicas del Estado peruano.\n\n'
          'Puedo ayudarte con normativas, procesos de selección, requisitos del '
          'SEACE y más. Selecciona una pregunta sugerida o escribe tu consulta.',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    ));
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

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty || _isLoading) return;
    _inputController.clear();
    _inputFocus.unfocus();

    final uid = _authService.userId;
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
    try { await _firestoreService.saveMessage(uid, userMsg); } catch (_) {}

    try {
      final history = _messages
          .where((m) => !m.isLoading && !m.id.startsWith('welcome'))
          .toList();
      final res = await _chatService.sendMessage(
          message: text, userId: uid, history: history);
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
      await _firestoreService.saveMessage(uid, aiMsg);
      if (res.sources.isNotEmpty) _loadSources();
    } catch (e) {
      setState(() {
        _messages.remove(loading);
        _messages.add(ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          content:
              '**No se pudo conectar con el servidor.**\n\n'
              '${e.toString().replaceFirst('Exception: ', '')}\n\n'
              'Verifica que el servidor Python esté activo.',
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
        _serverConnected = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent(AppConfig.whatsappMessage);
    final uri = Uri.parse('https://wa.me/${AppConfig.whatsappNumber}?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Limpiar historial'),
        content: const Text('Se borrarán todos los mensajes. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) {
      await _firestoreService.clearHistory(_authService.userId);
      setState(() {
        _messages.clear();
        _addWelcome();
      });
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Salir')),
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

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w > 1024;
    final isTablet = w > 640 && w <= 1024;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F9),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isDesktop || isTablet),
            if (!_serverConnected) _buildBanner(),
            Expanded(
              child: Row(
                children: [
                  if (isDesktop) _buildSidePanel(wide: true),
                  if (isTablet) _buildSidePanel(wide: false),
                  Expanded(child: _buildChat()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Top bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool showSidePanel) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9ECF0))),
      ),
      child: Row(
        children: [
          // Logo
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
          const Expanded(
            child: Text(
              'Asistente de Contrataciones Públicas',
              style: TextStyle(color: AppTheme.textGray, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Botón fuentes en móvil
          if (!showSidePanel)
            IconButton(
              icon: Badge(
                isLabelVisible: _sources.isNotEmpty,
                label: Text('${_sources.length}'),
                child: const Icon(Icons.folder_open_outlined,
                    color: AppTheme.primaryBlue, size: 22),
              ),
              onPressed: _showSourcesModal,
              tooltip: 'Ver fuentes',
            ),
          // WhatsApp
          IconButton(
            icon: const Icon(Icons.support_agent,
                color: Color(0xFF25D366), size: 22),
            tooltip: 'Soporte WhatsApp',
            onPressed: _openWhatsApp,
          ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.tune,
                  color: AppTheme.primaryBlue, size: 22),
              tooltip: 'Panel admin',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminScreen())),
            ),
          // Avatar
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
        if (v == 'admin') Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminScreen()));
      },
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: AppTheme.primaryBlue,
          backgroundImage:
              photoUrl != null ? NetworkImage(photoUrl) : null,
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
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            Text(_authService.userEmail ?? '',
                style: const TextStyle(
                    color: AppTheme.textGray, fontSize: 11)),
            if (_isAdmin) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            'Servidor desconectado. Ejecuta: uvicorn main:app --reload',
            style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: _checkServer,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(60, 28)),
          child: Text('Reintentar',
              style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
      ]),
    );
  }

  // ─── Panel lateral de fuentes ─────────────────────────────────────────────
  Widget _buildSidePanel({required bool wide}) {
    return Container(
      width: wide ? 260 : 200,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE9ECF0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(children: [
              const Icon(Icons.folder_open_outlined,
                  color: AppTheme.primaryBlue, size: 18),
              const SizedBox(width: 8),
              Text(
                wide ? 'Fuentes OECE' : 'Fuentes',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textDark),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_sources.length}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _sources.isEmpty
                ? _buildEmptySources()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
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

  Widget _buildEmptySources() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sin documentos cargados.',
              style: TextStyle(color: AppTheme.textGray, fontSize: 12)),
          if (_isAdmin) ...[
            const SizedBox(height: 8),
            const Text(
                'Usa el panel admin para subir PDFs, DOCX o TXT.',
                style: TextStyle(color: AppTheme.textGray, fontSize: 11),
                maxLines: 3),
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
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9ECF0)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(ext,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            doc.source.replaceAll(RegExp(r'\.\w+$'), ''),
            style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: const [
          Icon(Icons.add_circle_outline,
              color: AppTheme.primaryBlue, size: 16),
          SizedBox(width: 8),
          Text('Agregar fuente',
              style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ─── Área de chat ─────────────────────────────────────────────────────────
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
                  itemCount: _messages.length +
                      (_messages.length == 1 ? 1 : 0),
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
                          border:
                              Border.all(color: const Color(0xFFD1D5DB)),
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
                style: const TextStyle(fontSize: 14.5, color: AppTheme.textDark),
                decoration: const InputDecoration(
                  hintText: 'Escribe tu consulta sobre contrataciones...',
                  hintStyle:
                      TextStyle(color: AppTheme.textGray, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                            color: AppTheme.primaryBlue.withOpacity(0.35),
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

// ─── Bottom sheet de fuentes (móvil) ─────────────────────────────────────────
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
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                  style: const TextStyle(fontSize: 13),
                ),
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
                  Navigator.push(context,
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
