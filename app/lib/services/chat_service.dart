import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/message_model.dart';

class RateLimitException implements Exception {
  final String message;
  const RateLimitException(this.message);
  @override
  String toString() => message;
}

class ChatResponse {
  final String response;
  final List<String> sources;
  final List<String> suggestedQuestions;

  ChatResponse({
    required this.response,
    this.sources = const [],
    this.suggestedQuestions = const [],
  });
}

class ChatService {
  final String _baseUrl = AppConfig.serverUrl;

  static const _chatTimeout = Duration(seconds: 250);

  // ── Streaming SSE ────────────────────────────────────────────────────────────
  // Devuelve un Stream de tokens. Al finalizar emite un evento especial
  // con el JSON completo (done=true, sources, suggested_questions).
  Stream<String> streamMessage({
    required String message,
    required String userId,
    required List<ChatMessage> history,
    String caseId = '',
  }) async* {
    final historyJson = history
        .where((m) => !m.isLoading)
        .map((m) => m.toJson())
        .toList();

    final uri = Uri.parse('$_baseUrl${AppConfig.chatStreamEndpoint}');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode({
        'message': message,
        'user_id': userId,
        'case_id': caseId,
        'conversation_history': historyJson,
      });

    final client = http.Client();
    try {
      final response = await client
          .send(request)
          .timeout(_chatTimeout);

      if (response.statusCode == 429) {
        throw RateLimitException(
          'El servicio de IA está temporalmente saturado. '
          'Por favor espera unos minutos e intenta de nuevo.',
        );
      }
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String detail;
        try {
          detail = jsonDecode(body)['detail'] ??
              'Error del servidor (${response.statusCode})';
        } catch (_) {
          detail = 'Error del servidor (${response.statusCode})';
        }
        throw Exception(detail);
      }

      // SSE: cada línea es "data: <json>\n\n"
      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        // Procesar líneas completas
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.startsWith('data: ')) {
            final raw = line.substring(6);
            try {
              final data = jsonDecode(raw);
              if (data['token'] != null) {
                yield data['token'] as String;
              } else if (data['done'] == true) {
                // Señal de fin: emitir JSON completo para que el caller extraiga sources y sugerencias
                yield '\x00DONE\x00$raw';
              } else if (data['error'] != null) {
                throw Exception(data['error']);
              }
            } catch (e) {
              if (e is Exception && e.toString().contains('error')) rethrow;
            }
          }
        }
      }
    } on TimeoutException {
      throw TimeoutException(
        'La respuesta tardó demasiado. El modelo puede estar cargando — intenta de nuevo.',
      );
    } on http.ClientException {
      throw Exception(
          'No se pudo conectar al servidor. Verifica que el servidor esté activo.');
    } finally {
      client.close();
    }
  }

  // ── Fallback no-streaming (para compatibilidad) ───────────────────────────
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
        final suggested = (data['suggested_questions'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        return ChatResponse(
          response: data['response'],
          sources: sources,
          suggestedQuestions: suggested,
        );
      } else if (response.statusCode == 504) {
        throw TimeoutException('El servidor tardó demasiado en responder.');
      } else if (response.statusCode == 429) {
        throw RateLimitException(
          'El servicio de IA está temporalmente saturado. '
          'Por favor espera unos minutos e intenta de nuevo.',
        );
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
