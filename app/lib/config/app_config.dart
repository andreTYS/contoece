class AppConfig {
  static const bool demoMode = false;

  static const String serverUrl = 'https://oece.masredespro.com/api';

  static const String whatsappNumber = '51910561256';
  static const String whatsappMessage =
      'Hola, necesito soporte con el Asistente IA de Contrataciones OECE.';

  static const String appName = 'OECE-IA';
  static const String appSubtitle = 'Asistente de Contrataciones';
  static const String appVersion = '1.0.0';

  static const String chatEndpoint = '/chat';
  static const String healthEndpoint = '/health';
  static const String adminDocumentsEndpoint = '/admin/documents';
  static const String adminUploadEndpoint = '/admin/upload';
  static const String adminDeleteEndpoint = '/admin/document';

  static const String userDocumentsEndpoint = '/user/documents';
  static const String userUploadEndpoint = '/user/upload';
  static const String userDeleteEndpoint = '/user/document';

  static const String googleWebClientId =
      '1036373712732-o5h249bo1fdlstjlmjo1ml9smnj76ai2.apps.googleusercontent.com';

  static const List<String> adminEmails = [
    'andretys1000@gmail.com',
  ];

  static const List<String> allowedDomains = [
    'oece.gob.pe',
    'contrataciones.gob.pe',
    'gmail.com',
  ];

  static bool isEmailAllowed(String email) {
    if (allowedDomains.isEmpty) return true;
    final domain = email.split('@').last.toLowerCase();
    return allowedDomains.contains(domain);
  }
}
