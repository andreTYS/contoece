import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';
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
    final ref = _db!.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      final role = AppConfig.adminEmails.contains(email.toLowerCase())
          ? 'admin'
          : 'user';
      await ref.set({
        'email': email,
        'displayName': displayName,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
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

  Future<List<Map<String, dynamic>>> listUsers() async {
    if (AppConfig.demoMode) {
      // Usuarios ficticios para demo
      return [
        {
          'uid': 'demo-user-oece',
          'displayName': 'Usuario Demo',
          'email': 'demo@oece.gob.pe',
          'role': 'admin',
        },
        {
          'uid': 'demo-user-2',
          'displayName': 'María García',
          'email': 'mgarcia@oece.gob.pe',
          'role': 'user',
        },
        {
          'uid': 'demo-user-3',
          'displayName': 'Carlos Ríos',
          'email': 'crios@contrataciones.gob.pe',
          'role': 'user',
        },
      ];
    }
    final snap = await _db!
        .collection('users')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
  }

  // ─── Historial de conversaciones ────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _messagesRef(String uid) =>
      _db!.collection('conversations').doc(uid).collection('messages');

  Future<void> saveMessage(String uid, ChatMessage message) async {
    if (AppConfig.demoMode) return; // En demo no se persiste
    await _messagesRef(uid).doc(message.id).set({
      'content': message.content,
      'role': message.role == MessageRole.user ? 'user' : 'assistant',
      'timestamp': Timestamp.fromDate(message.timestamp),
      'sources': message.sources,
    });
  }

  Future<List<ChatMessage>> loadHistory(String uid, {int limit = 50}) async {
    if (AppConfig.demoMode) return []; // Demo empieza con chat vacío
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
  }

  Stream<List<ChatMessage>> historyStream(String uid) {
    if (AppConfig.demoMode) return Stream.value([]);
    return _messagesRef(uid)
        .orderBy('timestamp', descending: false)
        .limitToLast(100)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              return ChatMessage(
                id: doc.id,
                content: data['content'] as String,
                role: data['role'] == 'user'
                    ? MessageRole.user
                    : MessageRole.assistant,
                timestamp: (data['timestamp'] as Timestamp).toDate(),
                sources: List<String>.from(data['sources'] ?? []),
              );
            }).toList());
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
