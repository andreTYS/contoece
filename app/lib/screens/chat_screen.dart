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
  final List<ChatMessage> _messages = [];
  List<DocumentInfo> _sources = [];

  bool _isLoading = false;
  bool _serverConnected = false;
  bool _historyLoaded = false;
  bool _sourcesExpanded = true;

  bool get _isAdmin => widget.role == 'admin';

  static const List<String> _suggestedQuestions = [
    '¿Cuáles son los tipos de procedimientos de selección?',
    '¿Qué es el SEACE y cómo funciona?',
    '¿Cuáles son los requisitos para ser proveedor del Estado?',
    '¿Qué dice la Ley N° 30225 sobre contrataciones directas?',
    '¿Cómo se calcula el valor referencial en una licitación?',
    '¿Cuáles son las causales de descalificación de un postor?',
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
    super.dispose();
  }

  Future<void> _loadSources() async {
    try {
      final docs = await _adminService.listDocuments();
      if (mounted) setState(() => _sources = docs);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final uid = _authService.userId;
    final history = await _firestoreService.loadHistory(uid);
    setState(() {
      _historyLoaded = true;
      if (history.isEmpty) _addWelcomeMessage();
      else _messages.addAll(history);
    });
    _scrollToBottom();
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
      content:
          'Hola, soy **OECE-IA**, tu asistente especializado en contrataciones públicas del Estado peruano.\n\n'
          'Puedo ayudarte a entender normativas, procesos de selección, requisitos del SEACE y más. '
          'Selecciona una pregunta sugerida o escribe tu consulta.',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _checkServer() async {
    final connected = await _chatService.checkServerHealth();
    if (mounted) setState(() => _serverConnected = connected);
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

  Future<void> _sendMessage([String? text]) async {
    final msg = (text ?? _inputController.text).trim();
    if (msg.isEmpty || _isLoading) return;
    _inputController.clear();
    final uid = _authService.userId;

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: msg,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );
    final loadingMsg = ChatMessage(
      id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(loadingMsg);
      _isLoading = true;
    });
    _scrollToBottom();
    await _firestoreService.saveMessage(uid, userMsg);

    try {
      final history = _messages
          .where((m) => !m.isLoading && !m.id.startsWith('welcome'))
          .toList();
      final response = await _chatService.sendMessage(
        message: msg,
        userId: uid,
        history: history,
      );
      final aiMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: response.response,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        sources: response.sources,
      );
      setState(() {
        _messages.remove(loadingMsg);
        _messages.add(aiMsg);
        _isLoading = false;
        _serverConnected = true;
      });
      await _firestoreService.saveMessage(uid, aiMsg);
      if (response.sources.isNotEmpty) _loadSources();
    } catch (e) {
      setState(() {
        _messages.remove(loadingMsg);
        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content:
              '**Error al conectar con el servidor.**\n\n${e.toString().replaceFirst('Exception: ', '')}\n\nVerifica que el servidor esté activo.',
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
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar historial'),
        content: const Text('¿Borrar todas las conversaciones?'),
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
    if (confirm == true) {
      await _firestoreService.clearHistory(_authService.userId);
      setState(() { _messages.clear(); _addWelcomeMessage(); });
    }
  }

  Future<void> _signOut() async {
    if (AppConfig.demoMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Modo demo — cambia demoMode a false en app_config.dart para activar login.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await _authService.signOut();
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F9),
      body: Column(
        children: [
          _buildTopBar(),
          if (!_serverConnected) _buildServerBanner(),
          Expanded(
            child: isWide
                ? Row(children: [
                    _buildSourcesPanel(),
                    Expanded(child: _buildChatArea()),
                  ])
                : _buildChatArea(),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar (estilo NotebookLM) ──────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'OECE-IA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1),
            ),
          ),
          const SizedBox(width: 10),
          const Text('Asistente de Contrataciones Públicas',
              style: TextStyle(color: AppTheme.textGray, fontSize: 13)),
          const Spacer(),
          // WhatsApp
          IconButton(
            icon: const Icon(Icons.support_agent, color: Color(0xFF25D366), size: 22),
            tooltip: 'Soporte WhatsApp',
            onPressed: _openWhatsApp,
          ),
          // Admin
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.tune, color: AppTheme.primaryBlue, size: 22),
              tooltip: 'Panel admin',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
            ),
          // Avatar menu
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _signOut();
              if (v == 'clear') _clearChat();
              if (v == 'admin') Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
            },
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryBlue,
              child: Text(
                _authService.userDisplayName.isNotEmpty ? _authService.userDisplayName[0].toUpperCase() : 'U',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'profile',
                enabled: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_authService.userDisplayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(_authService.userEmail ?? '',
                      style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                ]),
              ),
              const PopupMenuDivider(),
              if (_isAdmin)
                const PopupMenuItem(value: 'admin', child: Row(children: [
                  Icon(Icons.tune, size: 16, color: AppTheme.accentGold),
                  SizedBox(width: 8), Text('Panel admin'),
                ])),
              const PopupMenuItem(value: 'clear', child: Row(children: [
                Icon(Icons.delete_outline, size: 16, color: AppTheme.textGray),
                SizedBox(width: 8), Text('Limpiar historial'),
              ])),
              const PopupMenuItem(value: 'logout', child: Row(children: [
                Icon(Icons.logout, size: 16, color: Colors.red),
                SizedBox(width: 8), Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
              ])),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── Server banner ────────────────────────────────────────────────────────

  Widget _buildServerBanner() {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(
          'Servidor desconectado. Ejecuta uvicorn main:app --reload en la carpeta server.',
          style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
        )),
        TextButton(
          onPressed: _checkServer,
          child: Text('Reintentar', style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  // ─── Panel de fuentes (izquierda) ─────────────────────────────────────────

  Widget _buildSourcesPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: _sourcesExpanded ? 260 : 52,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _sourcesExpanded = !_sourcesExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                const Icon(Icons.folder_open, color: AppTheme.primaryBlue, size: 20),
                if (_sourcesExpanded) ...[
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Fuentes OECE',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark)),
                  ),
                  Icon(Icons.chevron_left, color: AppTheme.textGray, size: 18),
                ],
              ]),
            ),
          ),
          const Divider(height: 1),
          if (_sourcesExpanded) ...[
            Expanded(
              child: _sources.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sin documentos cargados',
                            style: TextStyle(color: AppTheme.textGray, fontSize: 12)),
                        const SizedBox(height: 8),
                        if (_isAdmin)
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const AdminScreen())),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.lightBlue,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(children: [
                                Icon(Icons.add, size: 14, color: AppTheme.primaryBlue),
                                SizedBox(width: 4),
                                Text('Subir documentos',
                                    style: TextStyle(color: AppTheme.primaryBlue, fontSize: 12)),
                              ]),
                            ),
                          ),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _sources.length,
                      itemBuilder: (_, i) => _buildSourceTile(_sources[i]),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${_sources.length} documento(s) · ${_sources.fold(0, (s, d) => s + d.chunks)} fragmentos',
                style: const TextStyle(color: AppTheme.textGray, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceTile(DocumentInfo doc) {
    final ext = doc.source.split('.').last.toUpperCase();
    final color = ext == 'PDF' ? Colors.red.shade700 : ext == 'DOCX' ? Colors.blue.shade700 : Colors.green.shade700;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(ext, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(
          doc.source.replaceAll(RegExp(r'\.\w+$'), ''),
          style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        )),
      ]),
    );
  }

  // ─── Área de chat (derecha) ───────────────────────────────────────────────

  Widget _buildChatArea() {
    return Column(
      children: [
        Expanded(
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  itemCount: _messages.length + (_messages.length == 1 ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == 1 && _messages.length == 1) return _buildSuggestedQuestions();
                    return ChatBubble(message: _messages[i]);
                  },
                ),
        ),
        _buildInputArea(),
      ],
    );
  }

  // ─── Preguntas sugeridas (estilo NotebookLM) ──────────────────────────────

  Widget _buildSuggestedQuestions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Preguntas sugeridas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textGray)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestedQuestions
                .map((q) => GestureDetector(
                      onTap: () => _sendMessage(q),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
                        ),
                        child: Text(q, style: const TextStyle(fontSize: 13, color: AppTheme.primaryBlue)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ─── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: TextField(
                controller: _inputController,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Consulta sobre contrataciones públicas...',
                  hintStyle: TextStyle(color: AppTheme.textGray, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _sendMessage(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isLoading ? AppTheme.textGray : AppTheme.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
