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

  Future<ChatResponse> sendMessage({
    required String message,
    required String userId,
    required List<ChatMessage> history,
  }) async {
    try {
      final historyJson = history
          .where((m) => !m.isLoading)
          .map((m) => m.toJson())
          .toList();

      final response = await http
          .post(
            Uri.parse('$_baseUrl${AppConfig.chatEndpoint}'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'message': message,
              'user_id': userId,
              'conversation_history': historyJson,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final sources = (data['sources'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        return ChatResponse(response: data['response'], sources: sources);
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } on http.ClientException {
      throw Exception(
          'No se pudo conectar al servidor. Verifica que el servidor esté activo.');
    } catch (e) {
      rethrow;
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
