class AppConfig {
  // ── MODO DEMO ──────────────────────────────────────────────────────────────
  // true  → salta Firebase/login, entra directo al chat (para ver el diseño)
  // false → flujo real con Google Sign-In y Firestore
  static const bool demoMode = true;

  // URL del servidor local (cambiar a dominio cuando se despliegue)
  static const String serverUrl = 'http://localhost:8000';

  // WhatsApp soporte
  static const String whatsappNumber = '51910561256';
  static const String whatsappMessage =
      'Hola, necesito soporte con el Asistente IA de Contrataciones OECE.';

  // App info
  static const String appName = 'OECE-IA';
  static const String appSubtitle = 'Asistente de Contrataciones';
  static const String appVersion = '1.0.0';

  // Endpoints
  static const String chatEndpoint = '/chat';
  static const String healthEndpoint = '/health';
  static const String adminDocumentsEndpoint = '/admin/documents';
  static const String adminUploadEndpoint = '/admin/upload';
  static const String adminDeleteEndpoint = '/admin/document';

  // Correos que reciben rol admin automáticamente al primer login
  // Agrega aquí los correos de los administradores
  static const List<String> adminEmails = [
    // 'admin@oece.gob.pe',
    // 'tucorreo@gmail.com',
  ];
}
