import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';
import '../models/case_model.dart';
import '../models/message_model.dart';

class FirestoreService {
  FirebaseFirestore? get _db =>
      AppConfig.demoMode ? null : FirebaseFirestore.instance;

  // ─── Roles ──────────────────────────────────────────────────────────────────

  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    if (AppConfig.demoMode) return;
    try {
      final ref = _db!.collection('users').doc(uid);
      final snap = await ref.get();
      final isHardAdmin = AppConfig.adminEmails.contains(email.toLowerCase());

      // Check pre-assigned role
      String role = isHardAdmin ? 'admin' : 'user';
      if (!isHardAdmin) {
        final preassigned = await getPreassignedRole(email);
        if (preassigned != null) role = preassigned;
      }

      if (!snap.exists) {
        await ref.set({
          'email': email,
          'displayName': displayName,
          'role': role,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
      } else {
        final updates = <String, dynamic>{'lastLoginAt': FieldValue.serverTimestamp()};
        if (isHardAdmin && snap.data()?['role'] != 'admin') {
          updates['role'] = 'admin';
        } else if (!isHardAdmin && snap.data()?['role'] == 'user' && role == 'admin') {
          updates['role'] = 'admin';
        }
        await ref.update(updates);
      }
    } catch (_) {}
  }

  Future<String> getUserRole(String uid) async {
    if (AppConfig.demoMode) return 'admin';
    try {
      final snap = await _db!.collection('users').doc(uid).get();
      return snap.data()?['role'] as String? ?? 'user';
    } catch (_) {
      return 'user';
    }
  }

  Stream<String> userRoleStream(String uid) {
    if (AppConfig.demoMode) return Stream.value('admin');
    return _db!.collection('users').doc(uid).snapshots().map(
          (snap) => snap.data()?['role'] as String? ?? 'user',
        );
  }

  Future<void> setUserRole(String uid, String role) async {
    if (AppConfig.demoMode) return;
    await _db!.collection('users').doc(uid).update({'role': role});
  }

  Future<void> updateLastLogin(String uid) async {
    if (AppConfig.demoMode) return;
    try {
      await _db!.collection('users').doc(uid).update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listUsers() async {
    if (AppConfig.demoMode) {
      return [
        {'uid': 'demo-user-oece', 'displayName': 'Usuario Demo', 'email': 'demo@oece.gob.pe', 'role': 'admin'},
        {'uid': 'demo-user-2', 'displayName': 'María García', 'email': 'mgarcia@oece.gob.pe', 'role': 'user'},
        {'uid': 'demo-user-3', 'displayName': 'Carlos Ríos', 'email': 'crios@contrataciones.gob.pe', 'role': 'user'},
      ];
    }
    final snap = await _db!.collection('users').orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
  }

  Stream<List<Map<String, dynamic>>> usersStream() {
    if (AppConfig.demoMode) {
      return Stream.value([
        {'uid': 'demo-user-oece', 'displayName': 'Usuario Demo', 'email': 'demo@oece.gob.pe', 'role': 'admin'},
        {'uid': 'demo-user-2', 'displayName': 'María García', 'email': 'mgarcia@oece.gob.pe', 'role': 'user'},
      ]);
    }
    // Sin orderBy para evitar fallo cuando el campo no existe en todos los docs
    return _db!
        .collection('users')
        .snapshots()
        .map((snap) {
          final docs = snap.docs
              .map((d) => {'uid': d.id, ...d.data()})
              .toList();
          // Ordenar en cliente: primero por lastLoginAt, luego createdAt
          docs.sort((a, b) {
            final aTs = a['lastLoginAt'] ?? a['createdAt'];
            final bTs = b['lastLoginAt'] ?? b['createdAt'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            try {
              final aDt = (aTs as dynamic).toDate() as DateTime;
              final bDt = (bTs as dynamic).toDate() as DateTime;
              return bDt.compareTo(aDt);
            } catch (_) {
              return 0;
            }
          });
          return docs;
        });
  }

  // Registra manualmente un perfil de usuario por correo (para usuarios
  // que ya se loguearon en Firebase Auth pero no tienen perfil en Firestore)
  Future<void> registerUserProfile({
    required String email,
    String? displayName,
    String role = 'user',
  }) async {
    if (AppConfig.demoMode) return;
    final isAdmin = AppConfig.adminEmails.contains(email.toLowerCase());
    final effectiveRole = isAdmin ? 'admin' : role;
    // Buscar si ya existe por email
    final existing = await _db!
        .collection('users')
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      // Actualizar rol si es diferente
      await existing.docs.first.reference.update({'role': effectiveRole});
      return;
    }
    // Crear nuevo perfil sin uid real (placeholder hasta que el usuario se loguee)
    final docId = 'pending_${email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    await _db!.collection('users').doc(docId).set({
      'email': email.toLowerCase(),
      'displayName': displayName ?? email.split('@').first,
      'role': effectiveRole,
      'createdAt': FieldValue.serverTimestamp(),
      'isPending': true,
    });
  }

  // ─── Pre-asignación de roles por correo ───────────────────────────────────

  Future<void> preassignRole(String email, String role) async {
    if (AppConfig.demoMode) return;
    final key = email.toLowerCase().replaceAll('.', '_dot_').replaceAll('@', '_at_');
    await _db!.collection('email_roles').doc(key).set({
      'email': email.toLowerCase(),
      'role': role,
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> getPreassignedRole(String email) async {
    if (AppConfig.demoMode) return null;
    try {
      final key = email.toLowerCase().replaceAll('.', '_dot_').replaceAll('@', '_at_');
      final snap = await _db!.collection('email_roles').doc(key).get();
      return snap.data()?['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  Stream<List<Map<String, dynamic>>> preassignedRolesStream() {
    if (AppConfig.demoMode) return Stream.value([]);
    return _db!
        .collection('email_roles')
        .orderBy('assignedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> deletePreassignedRole(String email) async {
    if (AppConfig.demoMode) return;
    final key = email.toLowerCase().replaceAll('.', '_dot_').replaceAll('@', '_at_');
    await _db!.collection('email_roles').doc(key).delete();
  }

  // ─── Casos de usuario ────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _casesRef(String uid) =>
      _db!.collection('users').doc(uid).collection('cases');

  Future<List<CaseModel>> getCases(String uid) async {
    if (AppConfig.demoMode) return [];
    try {
      final snap = await _casesRef(uid).orderBy('createdAt', descending: true).get();
      return snap.docs.map((d) => CaseModel.fromMap(d.id, d.data())).toList();
    } catch (_) {
      return [];
    }
  }

  Stream<List<CaseModel>> casesStream(String uid) {
    if (AppConfig.demoMode) return Stream.value([]);
    return _casesRef(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CaseModel.fromMap(d.id, d.data())).toList());
  }

  Future<String> createCase(String uid, String name) async {
    if (AppConfig.demoMode) return 'demo-case';
    final ref = await _casesRef(uid).add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameCase(String uid, String caseId, String newName) async {
    if (AppConfig.demoMode) return;
    await _casesRef(uid).doc(caseId).update({'name': newName});
  }

  Future<void> deleteCase(String uid, String caseId) async {
    if (AppConfig.demoMode) return;
    final msgs = await _caseMsgsRef(uid, caseId).get();
    final batch = _db!.batch();
    for (final doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_casesRef(uid).doc(caseId));
    await batch.commit();
  }

  // ─── Historial por caso ──────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _caseMsgsRef(String uid, String caseId) =>
      _db!.collection('conversations').doc(uid).collection('cases').doc(caseId).collection('messages');

  Future<void> saveCaseMessage(String uid, String caseId, ChatMessage message) async {
    if (AppConfig.demoMode || caseId.isEmpty) return;
    await _caseMsgsRef(uid, caseId).doc(message.id).set({
      'content': message.content,
      'role': message.role == MessageRole.user ? 'user' : 'assistant',
      'timestamp': Timestamp.fromDate(message.timestamp),
      'sources': message.sources,
    });
  }

  Future<List<ChatMessage>> loadCaseHistory(String uid, String caseId, {int limit = 50}) async {
    if (AppConfig.demoMode || caseId.isEmpty) return [];
    try {
      final snap = await _caseMsgsRef(uid, caseId)
          .orderBy('timestamp', descending: false)
          .limitToLast(limit)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          content: data['content'] as String,
          role: data['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
          sources: List<String>.from(data['sources'] ?? []),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearCaseHistory(String uid, String caseId) async {
    if (AppConfig.demoMode || caseId.isEmpty) return;
    final snap = await _caseMsgsRef(uid, caseId).get();
    final batch = _db!.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ─── Historial global (admin / legacy) ──────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _messagesRef(String uid) =>
      _db!.collection('conversations').doc(uid).collection('messages');

  Future<void> saveMessage(String uid, ChatMessage message) async {
    if (AppConfig.demoMode) return;
    await _messagesRef(uid).doc(message.id).set({
      'content': message.content,
      'role': message.role == MessageRole.user ? 'user' : 'assistant',
      'timestamp': Timestamp.fromDate(message.timestamp),
      'sources': message.sources,
    });
  }

  Future<List<ChatMessage>> loadHistory(String uid, {int limit = 50}) async {
    if (AppConfig.demoMode) return [];
    try {
      final snap = await _messagesRef(uid)
          .orderBy('timestamp', descending: false)
          .limitToLast(limit)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          content: data['content'] as String,
          role: data['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
          sources: List<String>.from(data['sources'] ?? []),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearHistory(String uid) async {
    if (AppConfig.demoMode) return;
    final snap = await _messagesRef(uid).get();
    final batch = _db!.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
