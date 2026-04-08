import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_config.dart';
import '../models/message_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Roles ──────────────────────────────────────────────────────────────────

  /// Crea o actualiza el perfil del usuario al hacer login.
  /// Si el correo está en adminEmails, recibe rol admin automáticamente.
  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      final role =
          AppConfig.adminEmails.contains(email.toLowerCase()) ? 'admin' : 'user';
      await ref.set({
        'email': email,
        'displayName': displayName,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Retorna el rol del usuario: 'admin' | 'user'
  Future<String> getUserRole(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return snap.data()?['role'] as String? ?? 'user';
    } catch (_) {
      return 'user';
    }
  }

  /// Stream del rol para detectar cambios en tiempo real
  Stream<String> userRoleStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map(
          (snap) => snap.data()?['role'] as String? ?? 'user',
        );
  }

  /// Cambia el rol de un usuario (solo lo puede llamar un admin)
  Future<void> setUserRole(String uid, String role) async {
    await _db.collection('users').doc(uid).update({'role': role});
  }

  /// Lista todos los usuarios (para panel admin)
  Future<List<Map<String, dynamic>>> listUsers() async {
    final snap = await _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((d) => {'uid': d.id, ...d.data()})
        .toList();
  }

  // ─── Historial de conversaciones ────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _messagesRef(String uid) =>
      _db.collection('conversations').doc(uid).collection('messages');

  /// Guarda un mensaje en Firestore
  Future<void> saveMessage(String uid, ChatMessage message) async {
    await _messagesRef(uid).doc(message.id).set({
      'content': message.content,
      'role': message.role == MessageRole.user ? 'user' : 'assistant',
      'timestamp': Timestamp.fromDate(message.timestamp),
      'sources': message.sources,
    });
  }

  /// Carga los últimos N mensajes del historial
  Future<List<ChatMessage>> loadHistory(String uid, {int limit = 50}) async {
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

  /// Stream del historial en tiempo real
  Stream<List<ChatMessage>> historyStream(String uid) {
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

  /// Borra toda la conversación de un usuario
  Future<void> clearHistory(String uid) async {
    final snap = await _messagesRef(uid).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
