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
  bool _loadingDocs = false;
  bool _loadingUsers = false;
  bool _uploading = false;
  String? _uploadStatus;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
    _loadUsers();
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await _firestoreService.listUsers();
      if (mounted) setState(() => _users = users);
    } catch (e) {
      _showError('Error al cargar usuarios: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
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

    int success = 0;
    int failed = 0;

    for (final file in result.files) {
      if (file.bytes == null) continue;
      try {
        setState(() => _uploadStatus = 'Procesando: ${file.name}');
        final res = await _adminService.uploadDocument(
          fileName: file.name,
          fileBytes: file.bytes!,
        );
        final chunks = res['chunks_added'] ?? 0;
        setState(() => _uploadStatus = '${file.name}: $chunks chunks añadidos');
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
        content: Text(
            '¿Eliminar "${doc.source}" (${doc.chunks} chunks) de la base?'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${doc.source}" eliminado correctamente'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _showError('Error al eliminar: $e');
    }
  }

  Future<void> _changeUserRole(Map<String, dynamic> user) async {
    final currentRole = user['role'] as String? ?? 'user';
    final newRole = currentRole == 'admin' ? 'user' : 'admin';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar rol'),
        content: Text(
          'Cambiar a "${user['displayName'] ?? user['email']}" '
          'de "$currentRole" a "$newRole"?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newRole == 'admin'
                  ? AppTheme.silver
                  : AppTheme.primaryRed,
            ),
            child: Text('Hacer $newRole'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _firestoreService.setUserRole(user['uid'] as String, newRole);
      await _loadUsers();
    } catch (e) {
      _showError('Error al cambiar rol: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryRed,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: AppTheme.silver),
            SizedBox(width: 8),
            Text('Panel de Administración',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.silver,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.folder_open), text: 'Documentos'),
            Tab(icon: Icon(Icons.people), text: 'Usuarios'),
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

  // ─── Tab Documentos ──────────────────────────────────────────────────────────

  Widget _buildDocumentsTab() {
    return Column(
      children: [
        _buildStatsBar(),
        if (_uploading) _buildUploadProgress(),
        Expanded(
          child: _loadingDocs
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryRed))
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
      width: double.infinity,
      color: AppTheme.lightBlue,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.storage, color: AppTheme.primaryRed, size: 18),
          const SizedBox(width: 8),
          Text(
            'Total en base: $total chunks  ·  ${_documents.length} documento(s)',
            style: const TextStyle(
              color: AppTheme.primaryRed,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              _loadDocuments();
              _loadStats();
            },
            icon: const Icon(Icons.refresh, size: 18, color: AppTheme.primaryRed),
            tooltip: 'Actualizar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgress() {
    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _uploadStatus ?? 'Procesando...',
              style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
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
      elevation: 2,
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
            child: Text(
              ext,
              style: TextStyle(
                  color: extColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        title: Text(
          doc.source,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textDark),
        ),
        subtitle: Text(
          '${doc.chunks} fragmentos indexados',
          style: const TextStyle(color: AppTheme.textGray, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Eliminar documento',
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
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('No hay documentos en la base',
              style: TextStyle(color: AppTheme.textGray, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Sube PDFs, DOCX o TXT con normativas OECE\npara que la IA los use como contexto.',
            textAlign: TextAlign.center,
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
            offset: const Offset(0, -2),
          ),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  // ─── Tab Usuarios ────────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    return _loadingUsers
        ? const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryRed))
        : _users.isEmpty
            ? const Center(
                child: Text('No hay usuarios registrados',
                    style: TextStyle(color: AppTheme.textGray)))
            : RefreshIndicator(
                onRefresh: _loadUsers,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildUserCard(_users[i]),
                ),
              );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = user['role'] as String? ?? 'user';
    final isAdmin = role == 'admin';
    final name = user['displayName'] as String? ?? 'Sin nombre';
    final email = user['email'] as String? ?? '';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              isAdmin ? AppTheme.silver : AppTheme.primaryRed,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'U',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppTheme.textDark)),
        subtitle: Text(email,
            style: const TextStyle(
                color: AppTheme.textGray, fontSize: 12)),
        trailing: GestureDetector(
          onTap: () => _changeUserRole(user),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isAdmin
                  ? AppTheme.silver.withOpacity(0.15)
                  : AppTheme.lightBlue,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isAdmin
                    ? AppTheme.silver
                    : AppTheme.primaryRed.withOpacity(0.4),
              ),
            ),
            child: Text(
              isAdmin ? 'Admin' : 'Usuario',
              style: TextStyle(
                color: isAdmin ? AppTheme.silver : AppTheme.primaryRed,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
