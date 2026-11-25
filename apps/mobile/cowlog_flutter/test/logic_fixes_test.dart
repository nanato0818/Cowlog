import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/services/api_client.dart';
import 'package:cowlog_flutter/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> cowJson(String id, String status, String number) => {
  'id': id,
  'name': number,
  'number': number,
  'device_id': 'dev-$id',
  'status': status,
  'reason': 'r',
};

String dashboardBody(List<Map<String, dynamic>> cows) =>
    jsonEncode({'generated_at': '2026-05-10T00:00:00Z', 'cows': cows});

String historyBody(String cowId, String date) =>
    jsonEncode({'cow_id': cowId, 'date': date, 'measurements': []});

AppStore makeStore(http.Client client) =>
    AppStore(
        httpClient: client,
        readToken: 'tok',
        clock: () => DateTime.utc(2026, 5, 10, 3),
      )
      ..demoMode = false
      ..baseUrl = 'https://example.test/';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CowStatus', () {
    test('order and labels', () {
      expect(CowStatus.values, [
        CowStatus.check,
        CowStatus.unknown,
        CowStatus.disconnected,
        CowStatus.insufficient,
        CowStatus.noData,
        CowStatus.learning,
        CowStatus.normal,
      ]);
      expect(CowStatus.unknown.label, '不明');
      expect(CowStatus.unknown.isDataProblem, isFalse);
    });
    test('fromWire', () {
      expect(CowStatusLabel.fromWire('normal'), CowStatus.normal);
      expect(CowStatusLabel.fromWire('no_data'), CowStatus.noData);
      expect(CowStatusLabel.fromWire('something_new'), CowStatus.unknown);
      expect(CowStatusLabel.fromWire(''), CowStatus.unknown);
    });
  });

  group('tolerant JSON', () {
    test('Measurement accepts doubles', () {
      final m = Measurement.fromJson({
        'measured_at': '2026-05-10T00:00:00Z',
        'activity_seconds': 12.0,
        'coverage_seconds': 300.0,
        'interval_seconds': 300,
      });
      expect(m.activitySeconds, 12);
      expect(m.coverageSeconds, 300);
    });
    test('Cow accepts float battery and null reason', () {
      final json = cowJson('a', 'normal', '1')
        ..['battery_percent'] = 85.0
        ..['reason'] = null;
      final cow = Cow.fromJson(json);
      expect(cow.batteryPercent, 85);
      expect(cow.reason, '');
    });
    test('CowPosition satellites as double', () {
      final p = CowPosition.fromJson({
        'latitude': 33,
        'longitude': 132,
        'measured_at': '2026-05-10T00:00:00Z',
        'satellites': 7.0,
      });
      expect(p.satellites, 7);
    });
  });

  group('AppStore refresh state', () {
    test('success clears both', () async {
      final store = makeStore(
        MockClient((_) async => http.Response(dashboardBody([]), 200)),
      );
      await store.refresh();
      expect(store.isOffline, isFalse);
      expect(store.errorMessage, isNull);
    });

    test('network exception without cache is offline', () async {
      final store = makeStore(
        MockClient((_) async => throw const SocketException('down')),
      );
      await store.refresh();
      expect(store.isOffline, isTrue);
      expect(store.errorMessage, isNotNull);
    });

    test('timeout is offline', () async {
      final store = makeStore(
        MockClient((_) async => throw TimeoutException('slow')),
      );
      await store.refresh();
      expect(store.isOffline, isTrue);
    });

    test('cached display is offline, then recovery clears', () async {
      var fail = false;
      final store = makeStore(
        MockClient((_) async {
          if (fail) throw http.ClientException('x');
          return http.Response(
            dashboardBody([cowJson('a', 'normal', '1')]),
            200,
          );
        }),
      );
      await store.refresh();
      fail = true;
      await store.refresh();
      expect(store.isOffline, isTrue);
      expect(store.dashboard, isNotNull);
      fail = false;
      await store.refresh();
      expect(store.isOffline, isFalse);
      expect(store.errorMessage, isNull);
    });

    test('ApiException (401) is not offline', () async {
      final store = makeStore(
        MockClient((_) async => http.Response('no', 401)),
      );
      await store.refresh();
      expect(store.isOffline, isFalse);
      expect(store.errorMessage, contains('401'));
    });

    test('config error is not offline', () async {
      final store =
          AppStore(
              httpClient: MockClient((_) async => http.Response('', 200)),
              readToken: '',
            )
            ..demoMode = false
            ..baseUrl = 'https://example.test/';
      await store.refresh();
      expect(store.isOffline, isFalse);
      expect(store.errorMessage, '閲覧用トークンを設定してください');
    });
  });

  group('dashboard sort', () {
    test('status index then displayNumber', () async {
      final store = makeStore(
        MockClient(
          (_) async => http.Response(
            dashboardBody([
              cowJson('a', 'normal', '0300'),
              cowJson('b', 'check', '0500'),
              cowJson('c', 'normal', '0100'),
              cowJson('d', 'check', '0200'),
              cowJson('e', 'weird', '0900'),
            ]),
            200,
          ),
        ),
      );
      await store.refresh();
      expect(store.dashboard!.cows.map((c) => c.id), ['d', 'b', 'e', 'c', 'a']);
    });

    test('demo mode is sorted', () async {
      final store = AppStore()..demoMode = true;
      await store.refresh();
      final cows = store.dashboard!.cows;
      for (var i = 1; i < cows.length; i++) {
        final a = cows[i - 1], b = cows[i];
        expect(
          a.status.index < b.status.index ||
              (a.status == b.status &&
                  a.displayNumber.compareTo(b.displayNumber) <= 0),
          isTrue,
        );
      }
    });
  });

  group('history cache', () {
    late int calls;
    late AppStore store;
    setUp(() {
      calls = 0;
      store = makeStore(
        MockClient((req) async {
          calls++;
          final segs = req.url.pathSegments;
          return http.Response(
            historyBody(
              segs[segs.length - 2],
              req.url.queryParameters['date']!,
            ),
            200,
          );
        }),
      );
    });

    test('past dates are cached, force bypasses', () async {
      final d = DateTime(2026, 5, 1);
      await store.history('c1', d);
      await store.history('c1', d);
      expect(calls, 1);
      await store.history('c1', d, force: true);
      expect(calls, 2);
      await store.history('c2', d);
      expect(calls, 3);
    });

    test("today (JST) is never cached", () async {
      final d = DateTime(2026, 5, 10);
      await store.history('c1', d);
      await store.history('c1', d);
      expect(calls, 2);
    });

    test('evicts oldest beyond 100', () async {
      for (var i = 0; i < 101; i++) {
        await store.history('c$i', DateTime(2026, 5, 1));
      }
      expect(calls, 101);
      await store.history('c100', DateTime(2026, 5, 1));
      expect(calls, 101); // still cached
      await store.history('c0', DateTime(2026, 5, 1));
      expect(calls, 102); // evicted
    });

    test('clearHistoryCache invalidates', () async {
      final d = DateTime(2026, 5, 1);
      await store.history('c1', d);
      store.clearHistoryCache();
      await store.history('c1', d);
      expect(calls, 2);
    });

    test('offline history sets isOffline and is not memoized', () async {
      var fail = false;
      final s = makeStore(
        MockClient((req) async {
          if (fail) throw const SocketException('x');
          return http.Response(historyBody('c1', '2026-05-01'), 200);
        }),
      );
      final d = DateTime(2026, 5, 1);
      await s.history('c1', d, force: true); // warms prefs cache
      fail = true;
      await s.history('c1', d, force: true);
      expect(s.isOffline, isTrue);
      expect(s.errorMessage, isNotNull);
    });
  });

  group('SharedPreferences history cache cap', () {
    test('keeps at most 60 history entries, oldest dropped', () async {
      final client = ApiClient(
        baseUrl: 'https://example.test/',
        token: 'tok',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/history')) {
            return http.Response(
              historyBody('x', req.url.queryParameters['date']!),
              200,
            );
          }
          return http.Response(dashboardBody([]), 200);
        }),
      );
      await client.dashboard();
      for (var i = 0; i < 65; i++) {
        await client.history(cowId: 'c$i', date: '2026-05-01');
      }
      final prefs = await SharedPreferences.getInstance();
      final history = prefs
          .getKeys()
          .where((k) => k.startsWith('cowlog_cache:') && k.contains('/history'))
          .toList();
      expect(history.length, 60);
      expect(history.any((k) => k.contains('/c0/history')), isFalse);
      expect(history.any((k) => k.contains('/c4/history')), isFalse);
      expect(history.any((k) => k.contains('/c5/history')), isTrue);
      expect(history.any((k) => k.contains('/c64/history')), isTrue);
      expect(
        prefs.getKeys().any(
          (k) => k == 'cowlog_cache:https://example.test/v1/dashboard',
        ),
        isTrue,
      );
    });
  });
}
