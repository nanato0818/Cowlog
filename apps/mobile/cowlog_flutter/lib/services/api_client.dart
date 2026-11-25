import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.token, this.httpClient});
  final http.Client? httpClient;
  bool usedCache = false;
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
    usedCache = false;
    final uri = _uri(path, query);
    final key = 'cowlog_cache:$uri';
    final prefs = await SharedPreferences.getInstance();
    try {
      final response =
          await (httpClient?.get(
                    uri,
                    headers: {'Authorization': 'Bearer $token'},
                  ) ??
                  http.get(uri, headers: {'Authorization': 'Bearer $token'}))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ApiException('サーバーが応答できませんでした（${response.statusCode}）');
      }
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body) as Map<String, dynamic>;
      // Validate before persisting.
      if (path == 'v1/dashboard') {
        Dashboard.fromJson(data);
      } else {
        CowHistory.fromJson(data);
      }
      await prefs.setString(key, body);
      await _trackHistoryKey(prefs, key);
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      final cached = prefs.getString(key);
      if (cached == null) rethrow;
      usedCache = true;
      return jsonDecode(cached) as Map<String, dynamic>;
    }
  }

  static const _orderKey = 'cowlog_cache_order';
  static const maxHistoryCacheEntries = 60;

  /// Remember write order of history cache keys and evict the oldest beyond the cap.
  Future<void> _trackHistoryKey(SharedPreferences prefs, String key) async {
    if (!key.contains('/history')) return;
    final order = [...(prefs.getStringList(_orderKey) ?? <String>[])];
    // Adopt history entries cached before tracking existed (treated as oldest).
    final known = order.toSet();
    final legacy = prefs.getKeys().where(
      (k) =>
          k.startsWith('cowlog_cache:') &&
          k.contains('/history') &&
          !known.contains(k),
    );
    order.insertAll(0, legacy.where((k) => k != key));
    order.remove(key);
    order.add(key);
    while (order.length > maxHistoryCacheEntries) {
      await prefs.remove(order.removeAt(0));
    }
    await prefs.setStringList(_orderKey, order);
  }

  // Registry and writes never fall back to cache: stale mappings must not be edited.
  Future<List<Collar>> collars() async {
    final response =
        await (httpClient?.get(
                  _uri('v1/collars'),
                  headers: {'Authorization': 'Bearer $token'},
                ) ??
                http.get(
                  _uri('v1/collars'),
                  headers: {'Authorization': 'Bearer $token'},
                ))
            .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException('首輪一覧を取得できません（${response.statusCode}）');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (data['collars'] as List)
        .map((j) => Collar.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCollar(
    String deviceId,
    String number,
    CowStyle style,
    String manageToken,
  ) async {
    if (manageToken.isEmpty) throw const ApiException('登録の権限がありません');
    final client = httpClient ?? http.Client();
    late http.Response response;
    try {
      response = await client
          .post(
            _uri('v1/collars'),
            headers: {
              'Authorization': 'Bearer $manageToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'device_id': deviceId,
              'number': number,
              'cow_style': style.name,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } finally {
      if (httpClient == null) client.close();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException(switch (response.statusCode) {
        409 => '首輪IDまたは番号は使用中です',
        401 || 403 => '登録の権限がありません',
        400 => '入力を確認してください',
        _ => '登録できませんでした',
      });
    }
    final result = jsonDecode(utf8.decode(response.bodyBytes));
    if (result['device_id'] != deviceId ||
        result['number'] != number ||
        result['cow_style'] != style.name ||
        result['saved_to'] != 'server') {
      throw const ApiException('登録結果を確認できません');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cowlog_cache:${_uri('v1/dashboard')}');
  }

  Future<void> setNumber(
    Collar collar,
    String number,
    String manageToken, {
    CowStyle? style,
  }) async {
    if (manageToken.isEmpty) throw const ApiException('番号設定の権限がありません');
    final client = httpClient ?? http.Client();
    late http.Response response;
    try {
      response = await client
          .put(
            _uri('v1/collars/${Uri.encodeComponent(collar.deviceId)}/number'),
            headers: {
              'Authorization': 'Bearer $manageToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'number': number,
              'expected_number': collar.number,
              if (style != null) 'cow_style': style.name,
              if (style != null) 'expected_style': collar.style.name,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } finally {
      if (httpClient == null) client.close();
    }
    if (response.statusCode != 200) {
      throw ApiException(switch (response.statusCode) {
        409 => '番号が使用中、または別の端末で変更されています。一覧を更新してください',
        401 || 403 => '番号設定の権限がありません',
        404 => '首輪が見つかりません。一覧を更新してください',
        400 => '番号は半角数字1〜12桁で入力してください',
        _ => '保存できませんでした（${response.statusCode}）',
      });
    }
    final result = jsonDecode(utf8.decode(response.bodyBytes));
    if (result['device_id'] != collar.deviceId ||
        result['number'] != number ||
        result['saved_to'] != 'server' ||
        (style != null && result['cow_style'] != style.name)) {
      throw const ApiException('保存結果を確認できません。一覧を更新してください');
    }
    final prefs = await SharedPreferences.getInstance();
    // Invalidate only this deployment's dashboard, otherwise offline reads can
    // resurrect the old number immediately after a successful edit.
    await prefs.remove('cowlog_cache:${_uri('v1/dashboard')}');
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
