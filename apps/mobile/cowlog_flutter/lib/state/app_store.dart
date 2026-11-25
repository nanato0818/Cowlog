import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../activity_summary.dart' show farmToday;
import '../models.dart';
import '../app_config.dart';
import '../services/api_client.dart';

const _offlineMessage = '通信できません。保存済みデータを表示中';

class AppStore extends ChangeNotifier {
  AppStore({this.httpClient, String? readToken, DateTime Function()? clock})
    : _readToken = readToken ?? AppConfig.readToken,
      _clock = clock ?? DateTime.now;

  /// Injectable for tests; production uses the default client.
  final http.Client? httpClient;
  final String _readToken;
  final DateTime Function() _clock;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Dashboard? dashboard;
  String? errorMessage;
  bool isOffline = false;
  bool isLoading = false;
  bool demoMode = AppConfig.demoMode;
  String baseUrl = AppConfig.apiUrl;

  Future<void>? _refreshJob;
  static const _historyCacheLimit = 100;
  // Insertion-ordered: oldest entries are first.
  final Map<String, CowHistory> _historyCache = {};

  static List<Cow> sortedCows(Iterable<Cow> cows) {
    final list = cows.toList();
    // Decorate with the original index so the sort is stable.
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final byStatus = a.$2.status.index.compareTo(b.$2.status.index);
      if (byStatus != 0) return byStatus;
      final byNumber = a.$2.displayNumber.compareTo(b.$2.displayNumber);
      return byNumber != 0 ? byNumber : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Anything except an [ApiException] (auth, configuration, bad status) is
  /// treated as a connectivity problem: timeouts, sockets, http client errors.
  static bool isNetworkError(Object error) =>
      error is! ApiException ||
      error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException;

  void clearHistoryCache() => _historyCache.clear();
  bool _savingNumber = false;
  final Map<String, String> _demoNumbers = {};
  final Map<String, CowStyle> _demoStyles = {};
  final Map<String, Cow> _demoAdded = {};
  bool get canManageNumbers => demoMode || AppConfig.manageToken.isNotEmpty;

  Future<List<Collar>> loadCollars() async {
    if (demoMode) {
      return (dashboard ?? DemoData.dashboard()).cows
          .where((c) => c.deviceId != null)
          .map(
            (c) => Collar(
              deviceId: c.deviceId!,
              number: c.displayNumber,
              style: c.style,
              lastSeenAt: c.latestMeasuredAt,
            ),
          )
          .toList();
    }
    return ApiClient(baseUrl: baseUrl, token: AppConfig.readToken).collars();
  }

  Future<void> addCollar(String device, String number, CowStyle style) async {
    device = device.trim();
    number = number.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$').hasMatch(device)) {
      throw const ApiException('首輪IDを確認してください');
    }
    if (!RegExp(r'^[0-9]{1,12}$').hasMatch(number)) {
      throw const ApiException('番号は半角数字1〜12桁');
    }
    if (_savingNumber) throw const ApiException('保存中です');
    _savingNumber = true;
    try {
      await _refreshJob;
      if (demoMode) {
        final existing = await loadCollars();
        final same = existing.where((c) => c.deviceId == device).firstOrNull;
        if (same != null && (same.number != number || same.style != style)) {
          throw const ApiException('首輪IDは使用中です');
        }
        if (existing.any((c) => c.deviceId != device && c.number == number)) {
          throw const ApiException('番号は使用中です');
        }
        if (same == null) {
          _demoAdded[device] = Cow(
            id: 'added-$device',
            name: number,
            number: number,
            style: style,
            deviceId: device,
            status: CowStatus.noData,
            reason: '測定データがありません',
          );
        }
      } else {
        await ApiClient(
          baseUrl: baseUrl,
          token: AppConfig.readToken,
        ).createCollar(device, number, style, AppConfig.manageToken);
        dashboard = null;
      }
      _historyCache.clear();
    } finally {
      _savingNumber = false;
    }
    await refresh();
  }

  Future<void> saveNumber(
    Collar collar,
    String number, {
    CowStyle? style,
  }) async {
    if (!RegExp(r'^[0-9]{1,12}$').hasMatch(number)) {
      throw const ApiException('番号は半角数字1〜12桁で入力してください');
    }
    if (_savingNumber) throw const ApiException('番号を保存中です');
    _savingNumber = true;
    try {
      // Finish any old read before committing/invalidation; never re-cache an old label.
      await _refreshJob;
      if (demoMode) {
        final current = await loadCollars();
        if (current.any(
          (c) => c.deviceId != collar.deviceId && c.number == number,
        )) {
          throw const ApiException('この番号は別の首輪で使用中です');
        }
        _demoNumbers[collar.deviceId] = number;
        if (style != null) _demoStyles[collar.deviceId] = style;
        _historyCache.clear();
      } else {
        await ApiClient(
          baseUrl: baseUrl,
          token: AppConfig.readToken,
        ).setNumber(collar, number, AppConfig.manageToken, style: style);
        // Remove the in-memory dashboard too; failed refresh cannot show old labels.
        dashboard = null;
      }
      _historyCache.clear();
    } finally {
      _savingNumber = false;
    }
    await refresh();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    // Never reuse a previous deployment's cache or UI-saved connection settings.
    final scope = '$demoMode|$baseUrl';
    final previousToken = await _secureStorage.read(key: 'cowlog_build_token');
    if (prefs.getString('cowlog_build_scope') != scope ||
        previousToken != AppConfig.readToken) {
      for (final key in prefs.getKeys()) {
        if (key.startsWith('cowlog_cache:')) await prefs.remove(key);
      }
      await prefs.setString('cowlog_build_scope', scope);
      await _secureStorage.write(
        key: 'cowlog_build_token',
        value: AppConfig.readToken,
      );
    }
    await refresh();
  }

  Future<void> refresh() {
    if (_savingNumber) return Future.value();
    return _refreshJob ??= _refreshOnce().whenComplete(
      () => _refreshJob = null,
    );
  }

  Future<void> _refreshOnce() async {
    isLoading = true;
    notifyListeners();
    if (demoMode) {
      final demo = DemoData.dashboard();
      dashboard = Dashboard(
        generatedAt: demo.generatedAt,
        cows: sortedCows(
          [...demo.cows, ..._demoAdded.values].map(
            (c) => Cow(
              id: c.id,
              name: c.name,
              number: _demoNumbers[c.deviceId] ?? c.displayNumber,
              style: _demoStyles[c.deviceId] ?? c.style,
              deviceId: c.deviceId,
              status: c.status,
              reason: c.reason,
              latestMeasuredAt: c.latestMeasuredAt,
              batteryPercent: c.batteryPercent,
              activityRatio: c.activityRatio,
              latestPosition: c.latestPosition,
            ),
          ),
        ),
      );
      errorMessage = null;
      isOffline = false;
      isLoading = false;
      notifyListeners();
      return;
    }
    try {
      final client = ApiClient(
        baseUrl: baseUrl,
        token: _readToken,
        httpClient: httpClient,
      );
      final loaded = await client.dashboard();
      dashboard = Dashboard(
        generatedAt: loaded.generatedAt,
        cows: sortedCows(loaded.cows),
      );
      isOffline = client.usedCache;
      errorMessage = client.usedCache ? _offlineMessage : null;
    } catch (error) {
      if (isNetworkError(error)) {
        isOffline = true;
        errorMessage = _offlineMessage;
      } else {
        isOffline = false;
        errorMessage = error.toString();
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<CowHistory> history(
    String cowId,
    DateTime date, {
    bool force = false,
  }) async {
    if (demoMode) {
      if (cowId.startsWith('added-')) {
        return CowHistory(
          cowId: cowId,
          date: FarmDate.format(date),
          measurements: [],
        );
      }
      return DemoData.history(cowId: cowId, date: date);
    }
    final dateText = FarmDate.format(date);
    final key = '$cowId$dateText';
    final cacheable = dateText != FarmDate.format(farmToday(_clock()));
    if (cacheable && !force) {
      final hit = _historyCache[key];
      if (hit != null) return hit;
    }
    final client = ApiClient(
      baseUrl: baseUrl,
      token: _readToken,
      httpClient: httpClient,
    );
    final result = await client.history(cowId: cowId, date: dateText);
    if (client.usedCache) {
      isOffline = true;
      errorMessage = _offlineMessage;
      notifyListeners();
    } else if (cacheable) {
      _historyCache.remove(key);
      _historyCache[key] = result;
      while (_historyCache.length > _historyCacheLimit) {
        _historyCache.remove(_historyCache.keys.first);
      }
    }
    return result;
  }
}

class DemoData {
  static const numbers = [
    '0199',
    '0201',
    '0204',
    '0205',
    '0212',
    '0215',
    '0216',
    '0218',
  ];
  static const statuses = [
    CowStatus.check,
    CowStatus.normal,
    CowStatus.disconnected,
    CowStatus.insufficient,
    CowStatus.learning,
    CowStatus.normal,
    CowStatus.normal,
    CowStatus.normal,
  ];
  static Dashboard dashboard() {
    final now = DateTime.now();
    return Dashboard(
      generatedAt: now,
      cows: List.generate(numbers.length, (i) {
        final stale = i == 2;
        final measured = now.subtract(Duration(minutes: stale ? 180 : 5));
        final point = coordinate(i, measured.hour * 12 + measured.minute ~/ 5);
        return Cow(
          id: 'demo-${i + 1}',
          name: numbers[i],
          number: numbers[i],
          style: (i == 2 || i == 4) ? CowStyle.brown : CowStyle.holstein,
          deviceId: 'sample-${i + 1}',
          status: statuses[i],
          reason: switch (statuses[i]) {
            CowStatus.check => '直近2時間の活動量が普段より低下しています',
            CowStatus.disconnected => '3時間測定が届いていません。位置は過去の記録です',
            CowStatus.insufficient => '測定に空白があります。活動量の比較には情報が不足しています',
            CowStatus.learning => '普段の活動量を学習中です',
            _ => '行動量に大きな低下はありません',
          },
          latestMeasuredAt: measured,
          batteryPercent: 85 - i * 8,
          activityRatio: i == 0
              ? .02
              : (i == 2 || i == 3 || i == 4 ? null : .28),
          latestPosition: i == 3
              ? null
              : CowPosition(
                  latitude: point.$1,
                  longitude: point.$2,
                  measuredAt: measured,
                  accuracyM: 12,
                ),
        );
      }),
    );
  }

  static (double, double) coordinate(int cow, int step) {
    // 醍醐牧場の実座標上の架空経路。実機GPSではない。
    final phase = (step % 144) / 144 * math.pi * 2;
    final movement = step % 48 >= 36 ? (step ~/ 48 * 48 + 36) : step;
    final t = (movement % 144) / 144 * math.pi * 2;
    return (
      33.49918782 + cow * .000008 + math.sin(t) * .00035,
      132.67402367 +
          cow * .00001 +
          math.sin(t * 2) * .00065 +
          math.cos(phase) * .00005,
    );
  }

  static CowHistory history({required String cowId, required DateTime date}) {
    final cow = int.parse(cowId.split('-').last) - 1;
    final start = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = FarmDate.format(date) == FarmDate.format(now);
    final data = <Measurement>[];
    for (var step = 1; step < 288; step++) {
      final time = start.add(Duration(minutes: step * 5));
      if (time.isAfter(now)) break;
      if (cow == 2 &&
          today &&
          time.isAfter(now.subtract(const Duration(hours: 3)))) {
        break;
      }
      // GNSS欠測と90分の通信空白も試す。
      if (step >= 108 && step <= 125) continue;
      final point = coordinate(cow, step);
      final missing = cow == 3 || step == 80;
      final low =
          cow == 0 &&
          today &&
          time.isAfter(now.subtract(const Duration(hours: 2)));
      data.add(
        Measurement(
          measuredAt: time,
          latitude: missing ? null : point.$1,
          longitude: missing ? null : point.$2,
          gpsAccuracyM: 12,
          activitySeconds: low ? 6 : (step % 48 >= 36 ? 12 : 84),
          coverageSeconds: cow == 3 ? 60 : 300,
          intervalSeconds: 300,
        ),
      );
    }
    return CowHistory(
      cowId: cowId,
      date: FarmDate.format(date),
      measurements: data,
    );
  }
}
