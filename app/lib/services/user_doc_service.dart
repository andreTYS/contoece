import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'admin_service.dart';

class UserDocService {
  final String _base = AppConfig.serverUrl;

  Future<List<DocumentInfo>> listDocuments(String userId, {String caseId = ''}) async {
    try {
      final params = {'user_id': userId, if (caseId.isNotEmpty) 'case_id': caseId};
      final uri = Uri.parse('$_base${AppConfig.userDocumentsEndpoint}').replace(queryParameters: params);
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return data.map((e) => DocumentInfo.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> uploadDocument({
    required String userId,
    required String caseId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    final uri = Uri.parse('$_base${AppConfig.userUploadEndpoint}');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..fields['case_id'] = caseId
      ..files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    String errMsg = 'Error del servidor (${res.statusCode})';
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      errMsg = body['detail'] ?? errMsg;
    } catch (_) {}
    throw Exception(errMsg);
  }

  /// Analiza un documento subido: resumen + cumplimiento normativo (streaming SSE).
  /// Emite tokens de texto; al final emite '\x00DONE\x00{json}' con suggested_questions.
  Stream<String> analyzeDocument({
    required String userId,
    required String caseId,
    required String sourceName,
  }) async* {
    final uri = Uri.parse('$_base${AppConfig.userAnalyzeEndpoint}');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..fields['case_id'] = caseId
      ..fields['source_name'] = sourceName;

    final client = http.Client();
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 180));
      if (streamed.statusCode != 200) {
        final body = await http.Response.fromStream(streamed);
        String detail = 'Error del servidor (${streamed.statusCode})';
        try { detail = jsonDecode(utf8.decode(body.bodyBytes))['detail'] ?? detail; } catch (_) {}
        throw Exception(detail);
      }
      String buffer = '';
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n\n');
          if (idx == -1) break;
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 2);
          if (!line.startsWith('data:')) continue;
          final raw = line.substring(5).trim();
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            if (data.containsKey('error')) throw Exception(data['error']);
            if (data['done'] == true) {
              yield '\x00DONE\x00$raw';
              return;
            }
            if (data.containsKey('token')) yield data['token'] as String;
          } catch (e) {
            if (e is Exception) rethrow;
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Future<void> deleteDocument(String userId, String sourceName) async {
    final encoded = Uri.encodeComponent(sourceName);
    final uri = Uri.parse('$_base${AppConfig.userDeleteEndpoint}/$encoded')
        .replace(queryParameters: {'user_id': userId});
    final res = await http.delete(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      String errMsg = 'Error al eliminar (${res.statusCode})';
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        errMsg = body['detail'] ?? errMsg;
      } catch (_) {}
      throw Exception(errMsg);
    }
  }
}
