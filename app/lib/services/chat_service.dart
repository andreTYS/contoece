import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/message_model.dart';

class ChatService {
  final String _baseUrl = AppConfig.serverUrl;

  /// SSE streaming via XHR onProgress — tokens arrive in real-time.
  Stream<Map<String, dynamic>> streamMessage({
    required String message,
    required String userId,
    required List<ChatMessage> history,
    String caseId = '',
  }) {
    final controller = StreamController<Map<String, dynamic>>();

    final historyJson = history
        .where((m) => !m.isLoading)
        .map((m) => m.toJson())
        .toList();

    final body = jsonEncode({
      'message': message,
      'user_id': userId,
      'case_id': caseId,
      'conversation_history': historyJson,
    });

    final request = html.HttpRequest();
    request.open('POST', '$_baseUrl/chat/stream');
    request.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
    request.timeout = 120000;

    var lastLength = 0;
    var lineBuffer = '';

    void processBuffer() {
      while (lineBuffer.contains('\n\n')) {
        final idx = lineBuffer.indexOf('\n\n');
        final block = lineBuffer.substring(0, idx);
        lineBuffer = lineBuffer.substring(idx + 2);
        for (final line in block.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              final data =
                  jsonDecode(line.substring(6)) as Map<String, dynamic>;
              if (!controller.isClosed) controller.add(data);
            } catch (_) {}
          }
        }
      }
    }

    request.onProgress.listen((_) {
      if (controller.isClosed) return;
      final text = request.responseText ?? '';
      if (text.length <= lastLength) return;
      lineBuffer += text.substring(lastLength);
      lastLength = text.length;
      processBuffer();
    });

    request.onLoad.listen((_) {
      final text = request.responseText ?? '';
      if (text.length > lastLength) {
        lineBuffer += text.substring(lastLength);
      }
      for (final line in lineBuffer.split('\n')) {
        if (line.startsWith('data: ')) {
          try {
            final data =
                jsonDecode(line.substring(6)) as Map<String, dynamic>;
            if (!controller.isClosed) controller.add(data);
          } catch (_) {}
        }
      }
      if (!controller.isClosed) controller.close();
    });

    request.onError.listen((_) {
      if (!controller.isClosed) {
        controller.addError(Exception(
            'No se pudo conectar al servidor. Verifica que el servidor esté activo.'));
        controller.close();
      }
    });

    request.onTimeout.listen((_) {
      if (!controller.isClosed) {
        controller.addError(
            Exception('Tiempo de espera agotado. El servidor tardó demasiado.'));
        controller.close();
      }
    });

    request.send(body);
    return controller.stream;
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
