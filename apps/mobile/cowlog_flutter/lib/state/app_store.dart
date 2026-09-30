import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/api_client.dart';

class AppStore extends ChangeNotifier {
  static const _demoModeKey = 'demo_mode';
  static const _baseUrlKey = 'base_url';
  static const _tokenKey = 'cowlog_read_token';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _preferences;
  Dashboard? dashboard;
  String? errorMessage;
  bool isLoading = false;
  bool demoMode = true;
  String baseUrl = '';

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    demoMode = _preferences?.getBool(_demoModeKey) ?? true;
    baseUrl = _preferences?.getString(_baseUrlKey) ?? '';
    await refresh();
  }

  Future<void> setDemoMode(bool value) async {
    demoMode = value;
    dashboard = null;
    errorMessage = null;
    await _preferences?.setBool(_demoModeKey, value);
    notifyListeners();
    await refresh();
  }

  Future<void> saveConnection({required String url, String? token}) async {
    baseUrl = url.trim();
    await _preferences?.setString(_baseUrlKey, baseUrl);
    if (token != null && token.isNotEmpty) {
      await _secureStorage.write(key: _tokenKey, value: token);
    }
    errorMessage = null;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    if (demoMode) {
      dashboard = DemoData.dashboard();
      errorMessage = null;
      isLoading = false;
      notifyListeners();
      return;
    }
    try {
      final token = await _secureStorage.read(key: _tokenKey) ?? '';
      dashboard = await ApiClient(baseUrl: baseUrl, token: token).dashboard();
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<CowHistory> history(String cowId, DateTime date) async {
    if (demoMode) return DemoData.history(cowId: cowId, date: date);
    final token = await _secureStorage.read(key: _tokenKey) ?? '';
    return ApiClient(
      baseUrl: baseUrl,
      token: token,
    ).history(cowId: cowId, date: FarmDate.format(date));
  }
}

class DemoData {
  static Dashboard dashboard() {
    final now = DateTime.now();
    return Dashboard(
      generatedAt: now,
      cows: [
        Cow(
          id: 'demo-1',
          name: 'サンプル牛 1',
          deviceId: 'sample-01',
          status: CowStatus.check,
          reason: '普段の同じ時間帯より行動量が低下しています',
          latestMeasuredAt: now.subtract(const Duration(minutes: 15)),
          batteryPercent: 76,
          activityRatio: 0.02,
          latestPosition: CowPosition(
            latitude: 35.000000,
            longitude: 139.000000,
            measuredAt: now.subtract(const Duration(minutes: 15)),
            accuracyM: 15,
          ),
        ),
        Cow(
          id: 'demo-2',
          name: 'サンプル牛 2',
          deviceId: 'sample-02',
          status: CowStatus.normal,
          reason: '行動量に大きな低下はありません',
          latestMeasuredAt: now.subtract(const Duration(minutes: 20)),
          batteryPercent: 64,
          activityRatio: 0.31,
          latestPosition: CowPosition(
            latitude: 35.001000,
            longitude: 139.002000,
            measuredAt: now.subtract(const Duration(minutes: 20)),
            accuracyM: 18,
          ),
        ),
      ],
    );
  }

  static CowHistory history({required String cowId, required DateTime date}) {
    final start = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final measurements = <Measurement>[];
    for (var index = 0; index < 96; index++) {
      final time = start.add(Duration(minutes: 15 * (index + 1)));
      if (time.isAfter(now)) break;
      final low =
          cowId == 'demo-1' &&
          time.isAfter(now.subtract(const Duration(hours: 2)));
      measurements.add(
        Measurement(
          measuredAt: time,
          latitude:
              35.000000 + index * 0.000015 + (cowId == 'demo-2' ? 0.001 : 0),
          longitude:
              139.000000 + index * 0.000025 + (cowId == 'demo-2' ? 0.002 : 0),
          gpsAccuracyM: 15,
          activitySeconds: low ? 20 : (index % 3 == 0 ? 380 : 170),
          coverageSeconds: 900,
          intervalSeconds: 900,
        ),
      );
    }
    return CowHistory(
      cowId: cowId,
      date: FarmDate.format(date),
      measurements: measurements,
    );
  }
}
