import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class DocumentInfo {
  final String source;
  final int chunks;
  final String? fileHash;

  DocumentInfo({required this.source, required this.chunks, this.fileHash});

  factory DocumentInfo.fromJson(Map<String, dynamic> json) => DocumentInfo(
        source: json['source'] as String,
        chunks: json['chunks'] as int,
        fileHash: json['file_hash'] as String?,
      );
}

class AdminService {
  final String _base = AppConfig.serverUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  /// Lista los documentos en la base vectorial
  Future<List<DocumentInfo>> listDocuments() async {
    final res = await http
        .get(Uri.parse('$_base${AppConfig.adminDocumentsEndpoint}'),
            headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      return data
          .map((e) => DocumentInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Error al obtener documentos: ${res.statusCode}');
  }

  /// Sube e ingesta un documento al servidor
  Future<Map<String, dynamic>> uploadDocument({
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    final uri = Uri.parse('$_base${AppConfig.adminUploadEndpoint}');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));

    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    final err =
        jsonDecode(utf8.decode(res.bodyBytes))['detail'] ?? 'Error desconocido';
    throw Exception(err);
  }

  /// Elimina un documento de la base vectorial
  Future<void> deleteDocument(String sourceName) async {
    final encoded = Uri.encodeComponent(sourceName);
    final res = await http
        .delete(
          Uri.parse('$_base${AppConfig.adminDeleteEndpoint}/$encoded'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      final err =
          jsonDecode(utf8.decode(res.bodyBytes))['detail'] ?? 'Error al eliminar';
      throw Exception(err);
    }
  }

  /// Estadísticas generales
  Future<Map<String, dynamic>> getStats() async {
    final res = await http
        .get(Uri.parse('$_base/stats'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    return {};
  }
}
