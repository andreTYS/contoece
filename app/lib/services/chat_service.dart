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

class ChatStreamChunk {
  final String? token;
  final List<String>? sources;
  final String? error;
  final bool done;

  ChatStreamChunk._({this.token, this.sources, this.error, this.done = false});

  factory ChatStreamChunk.token(String t) => ChatStreamChunk._(token: t);
  factory ChatStreamChunk.done({List<String> sources = const []}) =>
      ChatStreamChunk._(done: true, sources: sources);
  factory ChatStreamChunk.error(String e) => ChatStreamChunk._(error: e);
}

class ChatService {
  final String _baseUrl = AppConfig.serverUrl;

  /// Streaming: devuelve tokens conforme llegan de Claude (SSE).
  Stream<ChatStreamChunk> sendMessageStream({
    required String message,
    required String userId,
    required List<ChatMessage> history,
    String caseId = '',
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/chat/stream'),
      );
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode({
        'message': message,
        'user_id': userId,
        'case_id': caseId,
        'conversation_history': history
            .where((m) => !m.isLoading)
            .map((m) => m.toJson())
            .toList(),
      });

      final streamed =
          await client.send(request).timeout(const Duration(seconds: 60));

      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        String detail = 'Error del servidor: ${streamed.statusCode}';
        try {
          detail = jsonDecode(body)['detail'] ?? detail;
        } catch (_) {}
        yield ChatStreamChunk.error(detail);
        return;
      }

      String buffer = '';
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final parts = buffer.split('\n\n');
        buffer = parts.last;
        for (final part in parts.sublist(0, parts.length - 1)) {
          for (final line in part.split('\n')) {
            if (!line.startsWith('data: ')) continue;
            try {
              final data =
                  jsonDecode(line.substring(6)) as Map<String, dynamic>;
              if (data.containsKey('token')) {
                yield ChatStreamChunk.token(data['token'] as String);
              } else if (data['done'] == true) {
                yield ChatStreamChunk.done(
                  sources: List<String>.from(data['sources'] ?? []),
                );
              } else if (data.containsKey('error')) {
                yield ChatStreamChunk.error(data['error'] as String);
              }
            } catch (_) {}
          }
        }
      }
    } on http.ClientException {
      yield ChatStreamChunk.error(
          'No se pudo conectar al servidor. Verifica que el servidor esté activo.');
    } catch (e) {
      yield ChatStreamChunk.error(
          e.toString().replaceFirst('Exception: ', ''));
    } finally {
      client.close();
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
