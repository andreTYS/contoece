import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/message_model.dart';

class ChatResponse {
  final String response;
  final List<String> sources;

  ChatResponse({required this.response, this.sources = const []});
}

class ChatService {
  final String _baseUrl = AppConfig.serverUrl;

  // Margen de 10s sobre el presupuesto del backend (2×90s + 3s sleep + nginx = ~183s)
  static const _chatTimeout = Duration(seconds: 250);

  Future<ChatResponse> sendMessage({
    required String message,
    required String userId,
    required List<ChatMessage> history,
    String caseId = '',
  }) async {
    final historyJson = history
        .where((m) => !m.isLoading)
        .map((m) => m.toJson())
        .toList();

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl${AppConfig.chatEndpoint}'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'message': message,
              'user_id': userId,
              'case_id': caseId,
              'conversation_history': historyJson,
            }),
          )
          .timeout(_chatTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final sources = (data['sources'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        return ChatResponse(response: data['response'], sources: sources);
      } else if (response.statusCode == 504) {
        throw TimeoutException('El servidor tardó demasiado en responder.');
      } else {
        String detail;
        try {
          detail = jsonDecode(utf8.decode(response.bodyBytes))['detail'] ??
              'Error del servidor (${response.statusCode})';
        } catch (_) {
          detail = 'Error del servidor (${response.statusCode})';
        }
        throw Exception(detail);
      }
    } on TimeoutException {
      throw TimeoutException(
        'La respuesta tardó demasiado. El modelo puede estar cargando — intenta de nuevo.',
      );
    } on http.ClientException {
      throw Exception(
          'No se pudo conectar al servidor. Verifica que el servidor esté activo.');
    }
  }

  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl${AppConfig.healthEndpoint}'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
