import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final AdminService _adminService = AdminService();
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;

  List<DocumentInfo> _documents = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _preassigned = [];
  StreamSubscription<List<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<List<Map<String, dynamic>>>? _preassignedSub;

  bool _loadingDocs = false;
  bool _uploading = false;
  bool _usersPermissionError = false;
  String? _uploadStatus;
  Map<String, dynamic> _stats = {};
  String _userSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
    _loadStats();
    _subscribeUsers();
    _subscribePreassigned();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usersSub?.cancel();
    _preassignedSub?.cancel();
    super.dispose();
  }

  void _subscribeUsers() {
    _usersSub = _firestoreService.usersStream().listen((users) {
      if (mounted) setState(() { _users = users; _usersPermissionError = false; });
    }, onError: (e) {
      if (mounted) setState(() => _usersPermissionError = true);
    });
  }

  void _subscribePreassigned() {
    _preassignedSub =
        _firestoreService.preassignedRolesStream().listen((list) {
      if (mounted) setState(() => _preassigned = list);
    }, onError: (_) {});
  }

  Future<void> _loadDocuments() async {
    setState(() => _loadingDocs = true);
    try {
      final docs = await _adminService.listDocuments();
      if (mounted) setState(() => _documents = docs);
    } catch (e) {
      _showError('No se pudo conectar al servidor: $e');
    } finally {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _adminService.getStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _uploading = true;
      _uploadStatus = 'Subiendo ${result.files.length} archivo(s)...';
    });

    int success = 0, failed = 0;
    for (final file in result.files) {
      if (file.bytes == null) continue;
      try {
        setState(() => _uploadStatus = 'Procesando: ${file.name}');
        final res = await _adminService.uploadDocument(
            fileName: file.name, fileBytes: file.bytes!);
        final chunks = res['chunks_added'] ?? 0;
        setState(
            () => _uploadStatus = '${file.name}: $chunks chunks añadidos');
        success++;
      } catch (e) {
        failed++;
        _showError('Error con ${file.name}: $e');
      }
    }
    setState(() {
      _uploading = false;
      _uploadStatus =
          'Completado: $success subido(s)${failed > 0 ? ', $failed con error' : ''}';
    });
    await _loadDocuments();
    await _loadStats();
  }

  Future<void> _deleteDocument(DocumentInfo doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar documento'),
        content:
            Text('¿Eliminar "${doc.source}" (${doc.chunks} chunks) de la base?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _adminService.deleteDocument(doc.source);
      await _loadDocuments();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${doc.source}" eliminado'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      _showError('Error al eliminar: $e');
    }
  }

  Future<void> _changeUserRole(Map<String, dynamic> user) async {
    final currentRole = user['role'] as String? ?? 'user';
    final roles = ['user', 'admin'];
    String selected = currentRole;

    final confirm = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryRed,
              child: Text(
                ((user['displayName'] as String?) ?? 'U')[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user['displayName'] ?? 'Usuario',
                      style: const TextStyle(fontSize: 14)),
                  Text(user['email'] ?? '',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textGray)),
                ],
              ),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecciona el rol:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 12),
              ...roles.map((r) => RadioListTile<String>(
                    value: r,
                    groupValue: selected,
                    activeColor: AppTheme.primaryRed,
                    title: Text(_roleName(r),
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(_roleDescription(r),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textGray)),
                    onChanged: (v) => setDialog(() => selected = v!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  foregroundColor: Colors.white),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (confirm == null || confirm == currentRole) return;
    try {
      await _firestoreService.setUserRole(user['uid'] as String, confirm);
    } catch (e) {
      _showError('Error al cambiar rol: $e');
    }
  }

  Future<void> _showPreassignDialog() async {
    final emailCtrl = TextEditingController();
    String selectedRole = 'user';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.person_add_outlined,
                color: AppTheme.primaryRed, size: 20),
            SizedBox(width: 8),
            Text('Agregar / invitar usuario'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3EA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryRed.withOpacity(0.2)),
                ),
                child: const Text(
                  'Si el usuario ya se logueó con Google, aparecerá en la lista inmediatamente.\n'
                  'Si aún no se loguea, el rol quedará pre-asignado para cuando ingrese.',
                  style: TextStyle(color: AppTheme.textDark, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'usuario@dominio.com',
                  prefixIcon:
                      const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              const Text('Rol a asignar:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'user',
                      label: Text('Usuario'),
                      icon: Icon(Icons.person_outline, size: 16)),
                  ButtonSegment(
                      value: 'admin',
                      label: Text('Admin'),
                      icon: Icon(Icons.admin_panel_settings_outlined,
                          size: 16)),
                ],
                selected: {selectedRole},
                onSelectionChanged: (s) =>
                    setDialog(() => selectedRole = s.first),
                style: ButtonStyle(
                  backgroundColor:
                      WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTheme.primaryRed;
                    }
                    return null;
                  }),
                  foregroundColor:
                      WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return null;
                  }),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton.icon(
              onPressed: () async {
                final email = emailCtrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  _showError('Ingresa un correo válido');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  // Registra en Firestore (crea perfil si no existe) + pre-asigna rol
                  await Future.wait([
                    _firestoreService.preassignRole(email, selectedRole),
                    _firestoreService.registerUserProfile(
                        email: email, role: selectedRole),
                  ]);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '${_roleName(selectedRole)} registrado: $email'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                } catch (e) {
                  _showError('Error: $e');
                }
              },
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Guardar'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _roleName(String role) {
    switch (role) {
      case 'admin': return 'Administrador';
      case 'blocked': return 'Bloqueado';
      default: return 'Usuario';
    }
  }

  String _roleDescription(String role) {
    switch (role) {
      case 'admin': return 'Gestiona documentos y usuarios';
      case 'blocked': return 'Sin acceso al sistema';
      default: return 'Acceso a chat y sus casos';
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin': return const Color(0xFF6B21A8);
      case 'blocked': return Colors.red.shade700;
      default: return AppTheme.primaryRed;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.black,
        foregroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, color: AppTheme.primaryRed, size: 20),
          SizedBox(width: 8),
          Text('Panel de Administración',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryRed,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.folder_open, size: 16),
                const SizedBox(width: 6),
                const Text('Documentos'),
                const SizedBox(width: 6),
                if (_documents.isNotEmpty)
                  _TabBadge('${_documents.length}', AppTheme.primaryRed),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people, size: 16),
                const SizedBox(width: 6),
                const Text('Usuarios'),
                const SizedBox(width: 6),
                if (_users.isNotEmpty)
                  _TabBadge('${_users.length}', const Color(0xFF6B21A8)),
              ]),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDocumentsTab(),
          _buildUsersTab(),
        ],
      ),
    );
  }

  // ─── Tab Documentos ───────────────────────────────────────────────────────

  Widget _buildDocumentsTab() {
    return Column(
      children: [
        _buildStatsBar(),
        if (_uploading) _buildUploadProgress(),
        Expanded(
          child: _loadingDocs
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primaryRed))
              : _documents.isEmpty
                  ? _buildEmptyDocs()
                  : RefreshIndicator(
                      onRefresh: _loadDocuments,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _documents.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _buildDocumentCard(_documents[i]),
                      ),
                    ),
        ),
        _buildUploadButton(),
      ],
    );
  }

  Widget _buildStatsBar() {
    final total = _stats['total_documents'] ?? '—';
    return Container(
      color: AppTheme.lightBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        const Icon(Icons.storage, color: AppTheme.primaryRed, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Base: $total chunks  ·  ${_documents.length} documento(s)',
            style: const TextStyle(
                color: AppTheme.primaryRed,
                fontWeight: FontWeight.w600,
                fontSize: 12.5),
          ),
        ),
        IconButton(
          onPressed: () { _loadDocuments(); _loadStats(); },
          icon: const Icon(Icons.refresh,
              size: 18, color: AppTheme.primaryRed),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _buildUploadProgress() {
    return Container(
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(_uploadStatus ?? 'Procesando...',
              style: const TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _buildDocumentCard(DocumentInfo doc) {
    final ext = doc.source.split('.').last.toUpperCase();
    final extColor = ext == 'PDF'
        ? Colors.red.shade700
        : ext == 'DOCX'
            ? Colors.blue.shade700
            : Colors.green.shade700;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: extColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: extColor.withOpacity(0.3)),
          ),
          child: Center(
            child: Text(ext,
                style: TextStyle(
                    color: extColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        title: Text(doc.source,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppTheme.textDark)),
        subtitle: Text('${doc.chunks} fragmentos indexados',
            style:
                const TextStyle(color: AppTheme.textGray, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteDocument(doc),
        ),
      ),
    );
  }

  Widget _buildEmptyDocs() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('Sin documentos en la base',
              style: TextStyle(color: AppTheme.textGray, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            'Sube PDFs, DOCX o TXT con normativas OECE.',
            style: TextStyle(color: AppTheme.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _uploading ? null : _pickAndUpload,
          icon: const Icon(Icons.upload_file),
          label: const Text('Subir documentos (PDF / DOCX / TXT)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  // ─── Tab Usuarios ─────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    final admins = _users.where((u) => u['role'] == 'admin').length;
    final recent = _users.where((u) {
      final last = u['lastLoginAt'];
      if (last == null) return false;
      DateTime dt;
      try {
        dt = (last as dynamic).toDate();
      } catch (_) {
        return false;
      }
      return DateTime.now().difference(dt).inHours < 24;
    }).length;

    final filtered = _userSearch.isEmpty
        ? _users
        : _users.where((u) {
            final q = _userSearch.toLowerCase();
            return (u['email'] as String? ?? '').contains(q) ||
                (u['displayName'] as String? ?? '').toLowerCase().contains(q);
          }).toList();

    return Column(
      children: [
        // Permission error banner
        if (_usersPermissionError) _buildPermissionBanner(),
        // Stats header
        Container(
          color: AppTheme.black,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            _UserStat('${_users.length}', 'Total', Colors.white),
            const SizedBox(width: 20),
            _UserStat('$admins', 'Admin', const Color(0xFFD8B4FE)),
            const SizedBox(width: 20),
            _UserStat('$recent', 'Hoy', const Color(0xFF86EFAC)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _showPreassignDialog,
              icon: const Icon(Icons.person_add_outlined, size: 15),
              label: const Text('Invitar',
                  style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ]),
        ),
        // Search bar
        Container(
          color: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o correo...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.lightSilver)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.lightSilver)),
            ),
            onChanged: (v) => setState(() => _userSearch = v),
          ),
        ),
        // Pre-assigned section
        if (_preassigned.isNotEmpty) _buildPreassignedSection(),
        // User list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _userSearch.isEmpty
                        ? 'Sin usuarios registrados'
                        : 'Sin resultados para "$_userSearch"',
                    style: const TextStyle(color: AppTheme.textGray),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async =>
                      _subscribeUsers(), // triggers re-listen
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _buildUserCard(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sin permiso para leer usuarios',
                  style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
              Text(
                'Actualiza las reglas de Firestore en Firebase Console '
                'con el archivo firestore.rules del repositorio.',
                style: TextStyle(color: Colors.amber.shade800, fontSize: 11.5),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _usersPermissionError = false),
          child: const Text('OK', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildPreassignedSection() {
    return Container(
      color: const Color(0xFFF5F3FF),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_send_outlined,
                size: 14, color: Color(0xFF6B21A8)),
            const SizedBox(width: 6),
            Text(
              'Pre-asignaciones pendientes (${_preassigned.length})',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B21A8)),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _preassigned.map((p) {
              final email = p['email'] as String? ?? '';
              final role = p['role'] as String? ?? 'user';
              return Chip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text('$email · ${_roleName(role)}',
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.white,
                side: BorderSide(color: _roleColor(role).withOpacity(0.4)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () =>
                    _firestoreService.deletePreassignedRole(email),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = user['role'] as String? ?? 'user';
    final name = user['displayName'] as String? ?? 'Sin nombre';
    final email = user['email'] as String? ?? '';
    final lastLogin = user['lastLoginAt'];

    bool isRecent = false;
    String lastLoginText = 'Sin registro';
    if (lastLogin != null) {
      try {
        final dt = (lastLogin as dynamic).toDate() as DateTime;
        final diff = DateTime.now().difference(dt);
        isRecent = diff.inHours < 1;
        if (diff.inMinutes < 60) {
          lastLoginText = 'Hace ${diff.inMinutes} min';
        } else if (diff.inHours < 24) {
          lastLoginText = 'Hace ${diff.inHours}h';
        } else if (diff.inDays < 7) {
          lastLoginText = 'Hace ${diff.inDays} día${diff.inDays == 1 ? '' : 's'}';
        } else {
          lastLoginText =
              '${dt.day}/${dt.month}/${dt.year}';
        }
      } catch (_) {}
    }

    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _changeUserRole(user),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            // Avatar
            Stack(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _roleColor(role).withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
              if (isRecent)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: AppTheme.textDark)),
                  const SizedBox(height: 2),
                  Text(email,
                      style: const TextStyle(
                          color: AppTheme.textGray,
                          fontSize: 11.5),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.access_time,
                        size: 10, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text(lastLoginText,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: isRecent
                                ? const Color(0xFF16A34A)
                                : Colors.grey.shade400)),
                  ]),
                ],
              ),
            ),
            // Role badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _roleColor(role).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: _roleColor(role).withOpacity(0.3)),
              ),
              child: Text(_roleName(role),
                  style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Helpers UI ───────────────────────────────────────────────────────────────

class _TabBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TabBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _UserStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _UserStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.w900)),
      Text(label,
          style: TextStyle(
              color: color.withOpacity(0.6), fontSize: 10)),
    ]);
  }
}
