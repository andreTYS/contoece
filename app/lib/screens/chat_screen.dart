import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../models/message_model.dart';
import '../screens/admin_screen.dart';
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
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  bool _isLoading = false;
  bool _serverConnected = false;
  bool _historyLoaded = false;

  bool get _isAdmin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _checkServer();
    _loadHistory();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final uid = _authService.userId;
    final history = await _firestoreService.loadHistory(uid);

    setState(() {
      _historyLoaded = true;
      if (history.isEmpty) {
        _addWelcomeMessage();
      } else {
        _messages.addAll(history);
      }
    });

    _scrollToBottom();
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
      content:
          '¡Bienvenido/a al **Asistente IA de Contrataciones OECE**!\n\n'
          'Soy tu asistente especializado en **contrataciones públicas del Estado peruano**. '
          'Puedo ayudarte con:\n\n'
          '- Normativas y leyes de contrataciones\n'
          '- Procesos de selección y licitaciones\n'
          '- Documentos del SEACE\n'
          '- Requisitos para proveedores del Estado\n'
          '- Consultas sobre la Ley N° 30225 y su reglamento\n\n'
          '¿En qué puedo ayudarte hoy?',
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

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _inputController.clear();
    final uid = _authService.userId;

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );

    final loadingMessage = ChatMessage(
      id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(userMessage);
      _messages.add(loadingMessage);
      _isLoading = true;
    });
    _scrollToBottom();

    // Guardar mensaje del usuario en Firestore
    await _firestoreService.saveMessage(uid, userMessage);

    try {
      final historyForApi = _messages
          .where((m) => !m.isLoading && !m.id.startsWith('welcome'))
          .toList();

      final response = await _chatService.sendMessage(
        message: text,
        userId: uid,
        history: historyForApi,
      );

      final aiMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: response.response,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        sources: response.sources,
      );

      setState(() {
        _messages.remove(loadingMessage);
        _messages.add(aiMessage);
        _isLoading = false;
        _serverConnected = true;
      });

      // Guardar respuesta de la IA en Firestore
      await _firestoreService.saveMessage(uid, aiMessage);
    } catch (e) {
      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content:
            'Lo siento, ocurrió un error al procesar tu consulta.\n\n'
            '**Error:** ${e.toString().replaceFirst('Exception: ', '')}\n\n'
            'Por favor verifica que el servidor esté activo o contáctanos por WhatsApp.',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.remove(loadingMessage);
        _messages.add(errorMessage);
        _isLoading = false;
        _serverConnected = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _openWhatsApp() async {
    final message = Uri.encodeComponent(AppConfig.whatsappMessage);
    final url = 'https://wa.me/${AppConfig.whatsappNumber}?text=$message';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir WhatsApp'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar chat'),
        content: const Text(
            '¿Borrar todo el historial? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.clearHistory(_authService.userId);
      setState(() {
        _messages.clear();
        _addWelcomeMessage();
      });
    }
  }

  Future<void> _signOut() async {
    if (AppConfig.demoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo demo activo — login desactivado. Cambia demoMode a false en app_config.dart.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildServerStatus(),
          Expanded(
            child: !_historyLoaded
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primaryBlue))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => ChatBubble(message: _messages[i]),
                  ),
          ),
          _buildInputBar(),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _openWhatsApp,
        backgroundColor: const Color(0xFF25D366),
        tooltip: 'Soporte WhatsApp',
        child: const Icon(Icons.support_agent, color: Colors.white),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.primaryBlue,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentGold, width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.account_balance,
                  color: AppTheme.primaryBlue, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OECE-IA',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              Text('Asistente de Contrataciones',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ],
      ),
      actions: [
        // Badge admin
        if (_isAdmin)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.accentGold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppTheme.accentGold.withOpacity(0.6), width: 1),
            ),
            child: const Text('Admin',
                style: TextStyle(
                    color: AppTheme.accentGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        // Panel Admin
        if (_isAdmin)
          IconButton(
            icon: const Icon(Icons.admin_panel_settings,
                color: AppTheme.accentGold),
            tooltip: 'Panel de administración',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            ),
          ),
        // WhatsApp
        IconButton(
          icon: const Icon(Icons.support_agent, color: Color(0xFF25D366)),
          tooltip: 'Soporte WhatsApp',
          onPressed: _openWhatsApp,
        ),
        // Menú
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) {
            if (value == 'logout') _signOut();
            if (value == 'clear') _clearChat();
            if (value == 'admin') {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminScreen()));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'profile',
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_authService.userDisplayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(_authService.userEmail ?? '',
                      style: const TextStyle(
                          color: AppTheme.textGray, fontSize: 12)),
                  if (_isAdmin)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Administrador',
                          style: TextStyle(
                              color: AppTheme.accentGold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (_isAdmin)
              const PopupMenuItem(
                value: 'admin',
                child: Row(children: [
                  Icon(Icons.admin_panel_settings,
                      size: 18, color: AppTheme.accentGold),
                  SizedBox(width: 8),
                  Text('Panel de administración'),
                ]),
              ),
            const PopupMenuItem(
              value: 'clear',
              child: Row(children: [
                Icon(Icons.delete_outline, size: 18, color: AppTheme.textGray),
                SizedBox(width: 8),
                Text('Limpiar historial'),
              ]),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: Row(children: [
                Icon(Icons.logout, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServerStatus() {
    if (_serverConnected) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Servidor desconectado. Verifica que el servidor local esté activo.',
              style:
                  TextStyle(color: Colors.orange.shade800, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _checkServer,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text('Reintentar',
                style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Escribe tu consulta sobre contrataciones...',
                hintStyle:
                    TextStyle(color: AppTheme.textGray, fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide:
                      BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: Color(0xFFF9FAFB),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _isLoading
                    ? AppTheme.textGray
                    : AppTheme.primaryBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
