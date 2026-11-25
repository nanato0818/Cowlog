import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/route_segments.dart';
import 'package:cowlog_flutter/services/api_client.dart';
import 'package:cowlog_flutter/state/app_store.dart';
import 'package:cowlog_flutter/screens/dashboard_screen.dart';
import 'package:cowlog_flutter/screens/map_screen.dart';
import 'package:cowlog_flutter/screens/detail_screen.dart';

void main() {
  test('Route separates 65 minute gaps, missing GNSS and inaccurate fixes', () {
    final start = DateTime(2026, 10, 1);
    Measurement m(int minute, {double? lat = 35, double accuracy = 12}) =>
        Measurement(
          measuredAt: start.add(Duration(minutes: minute)),
          latitude: lat,
          longitude: 139,
          gpsAccuracyM: accuracy,
          activitySeconds: 10,
          coverageSeconds: 300,
          intervalSeconds: 300,
        );
    final segments = routeSegments([
      m(0),
      m(5),
      m(70),
      m(75),
      m(80, lat: null),
      m(85),
      m(90),
      m(95, accuracy: 101),
      m(100),
      m(105),
    ]);
    expect(segments.map((s) => s.length), [2, 2, 2, 2]);
  });
  test('Sample covers eight profiles, a curved route and GNSS gaps', () {
    expect(DemoData.dashboard().cows.length, 8);
    final h = DemoData.history(
      cowId: 'demo-1',
      date: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(h.measurements.where((m) => !m.hasUsableCoordinate), isNotEmpty);
    expect(routeSegments(h.measurements).length, greaterThan(1));
    final other = DemoData.history(
      cowId: 'demo-2',
      date: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(
      h.measurements.first.latitude,
      isNot(other.measurements.first.latitude),
    );
  });
  test(
    'Last successful dashboard survives client restart and network failure',
    () async {
      SharedPreferences.setMockInitialValues({});
      final body = jsonEncode({
        'generated_at': '2026-10-05T01:00:00Z',
        'cows': [],
      });
      final first = ApiClient(
        baseUrl: 'https://farm.example',
        token: 'test',
        httpClient: MockClient((_) async => http.Response(body, 200)),
      );
      await first.dashboard();
      final offline = ApiClient(
        baseUrl: 'https://farm.example',
        token: 'test',
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      );
      expect(
        (await offline.dashboard()).generatedAt,
        DateTime.parse('2026-10-05T01:00:00Z').toLocal(),
      );
      expect(offline.usedCache, isTrue);
      final denied = ApiClient(
        baseUrl: 'https://farm.example',
        token: 'bad',
        httpClient: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(denied.dashboard(), throwsA(isA<ApiException>()));
    },
  );
  testWidgets('Search narrows the list by herd number', (tester) async {
    final store = AppStore()..dashboard = DemoData.dashboard();
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(store: store)));
    await tester.enterText(find.byType(TextField), '0212');
    await tester.pump();
    expect(find.text('1 / 8頭'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(CowCard), matching: find.text('0212')),
      findsOneWidget,
    );
    expect(find.text('0199'), findsNothing);
  });
  testWidgets('Map marker opens individual information', (tester) async {
    final full = DemoData.dashboard();
    final store = AppStore()
      ..dashboard = Dashboard(
        generatedAt: full.generatedAt,
        cows: [full.cows.first],
      );
    await tester.pumpWidget(MaterialApp(home: MapScreen(store: store)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map-cow-demo-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('個体情報'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DetailScreen),
        matching: find.text('0199'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('個体の特徴'), findsNothing);
    await tester.scrollUntilVisible(
      find.byType(Slider),
      250,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await tester.pump();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, greaterThan(0));
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}
