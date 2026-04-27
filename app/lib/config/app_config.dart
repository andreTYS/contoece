class AppConfig {
  // ── MODO DEMO ──────────────────────────────────────────────────────────────
  // true  → salta Firebase/login, entra directo al chat (para ver el diseño)
  // false → flujo real con Google Sign-In y Firestore
  static const bool demoMode = false;

  static const String serverUrl = 'https://oece.masredespro.com/api';

  // WhatsApp soporte
  static const String whatsappNumber = '51910561256';
  static const String whatsappMessage =
      'Hola, necesito soporte con el Asistente IA de Contrataciones OECE.';

  // App info
  static const String appName = 'OECE-IA';
  static const String appSubtitle = 'Asistente de Contrataciones';
  static const String appVersion = '1.0.0';

  // Endpoints admin
  static const String chatEndpoint = '/chat';
  static const String healthEndpoint = '/health';
  static const String adminDocumentsEndpoint = '/admin/documents';
  static const String adminUploadEndpoint = '/admin/upload';
  static const String adminDeleteEndpoint = '/admin/document';

  // Endpoints usuario
  static const String userDocumentsEndpoint = '/user/documents';
  static const String userUploadEndpoint = '/user/upload';
  static const String userDeleteEndpoint = '/user/document';

  // Google Sign-In Web Client ID
  // Obtén el tuyo en: https://console.firebase.google.com
  // Proyecto → Authentication → Sign-in method → Google → Web SDK configuration
  static const String googleWebClientId =
      '1036373712732-o5h249bo1fdlstjlmjo1ml9smnj76ai2.apps.googleusercontent.com';

  // Correos que reciben rol admin automáticamente al primer login
  // Agrega aquí los correos de los administradores
  static const List<String> adminEmails = [
    'andretys1000@gmail.com',
  ];
}
