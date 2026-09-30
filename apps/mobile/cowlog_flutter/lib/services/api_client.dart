import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  const ApiClient({required this.baseUrl, required this.token});
  final String baseUrl;
  final String token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final configuredUrl = baseUrl.trim();
    final normalizedUrl = configuredUrl.endsWith('/')
        ? configuredUrl
        : '$configuredUrl/';
    final root = Uri.tryParse(normalizedUrl);
    if (root == null || root.host.isEmpty) {
      throw const ApiException('接続先URLを確認してください');
    }
    if (root.scheme.toLowerCase() != 'https') {
      throw const ApiException('HTTPSの接続先を指定してください');
    }
    if (token.isEmpty) {
      throw const ApiException('閲覧用トークンを設定してください');
    }
    return root.resolve(path).replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await http
        .get(_uri(path, query), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException('サーバーが応答できませんでした（${response.statusCode}）');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on FormatException {
      throw const ApiException('サーバーから受け取ったデータを読み取れませんでした');
    }
  }

  Future<Dashboard> dashboard() async =>
      Dashboard.fromJson(await _get('v1/dashboard'));
  Future<CowHistory> history({
    required String cowId,
    required String date,
  }) async => CowHistory.fromJson(
    await _get('v1/cows/${Uri.encodeComponent(cowId)}/history', {'date': date}),
  );
}
