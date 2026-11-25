import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cowlog_flutter/main.dart';
import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/screens/map_screen.dart';
import 'package:cowlog_flutter/state/app_store.dart';
import 'package:cowlog_flutter/services/api_client.dart';

void main() {
  testWidgets(
    'Map has no app name and adding a collar does not invent telemetry',
    (tester) async {
      final store = AppStore()..dashboard = DemoData.dashboard();
      await tester.pumpWidget(CowlogApp(store: store));
      expect(
        find.descendant(
          of: find.byType(MapScreen),
          matching: find.text('Cowlog'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('首輪・番号'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('首輪を追加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'collar-new-1');
      await tester.enterText(find.byType(TextField).at(1), '0099');
      await tester.tap(find.byKey(const ValueKey('cow-style-brown')));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('9台の首輪'), findsOneWidget);
      // 一覧は状態→番号順に並ぶので、番号で探す。
      final added = store.dashboard!.cows.firstWhere(
        (c) => c.deviceId == 'collar-new-1',
      );
      expect(added.displayNumber, '0099');
      expect(added.style, CowStyle.brown);
      expect(added.status, CowStatus.noData);
      expect(added.latestPosition, isNull);
      expect(
        (await store.history(added.id, DateTime.now())).measurements,
        isEmpty,
      );
      await store.addCollar('collar-new-1', '0099', CowStyle.brown); // retry
      expect(store.dashboard!.cows.length, 9);
      await expectLater(
        store.addCollar('different', '0099', CowStyle.holstein),
        throwsA(isA<ApiException>()),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Registration uses manage credential and verifies confirmation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = ApiClient(
        baseUrl: 'https://farm.example/prod/',
        token: 'read',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/prod/v1/collars');
          expect(request.headers['Authorization'], 'Bearer manage');
          expect(jsonDecode(request.body), {
            'device_id': 'collar-new',
            'number': '0099',
            'cow_style': 'brown',
          });
          return http.Response(
            jsonEncode({
              'device_id': 'collar-new',
              'number': '0099',
              'cow_style': 'brown',
              'saved_to': 'server',
            }),
            201,
          );
        }),
      );
      await client.createCollar('collar-new', '0099', CowStyle.brown, 'manage');
    },
  );
}
