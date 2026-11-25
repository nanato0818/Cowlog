import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cowlog_flutter/main.dart';
import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/state/app_store.dart';
import 'package:cowlog_flutter/services/api_client.dart';
import 'package:cowlog_flutter/widgets/cow_avatar.dart';

void main() {
  testWidgets(
    'Edit collar number updates dashboard, rejects duplicates, survives refresh',
    (tester) async {
      final store = AppStore()..dashboard = DemoData.dashboard();
      await tester.pumpWidget(CowlogApp(store: store));
      await tester.tap(find.text('首輪・番号'));
      await tester.pumpAndSettle();
      expect(find.textContaining('品種'), findsNothing);
      expect(find.textContaining('個体識別番号'), findsNothing);
      await tester.tap(find.byTooltip('番号を設定').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0007');
      await tester.tap(find.byKey(const ValueKey('cow-style-brown')));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('0007'), findsOneWidget);
      expect(store.dashboard!.cows.first.displayNumber, '0007');
      expect(store.dashboard!.cows.first.style, CowStyle.brown);
      await store.refresh();
      expect(store.dashboard!.cows.first.displayNumber, '0007');
      final collars = await store.loadCollars();
      await expectLater(
        store.saveNumber(collars[1], '0007'),
        throwsA(isA<ApiException>()),
      );
      await tester.tap(find.text('優先一覧'));
      await tester.pumpAndSettle();
      expect(find.text('0007'), findsOneWidget);
      expect(find.text('0199'), findsNothing);
      expect(
        tester
            .widgetList<CowAvatar>(find.byType(CowAvatar))
            .any((w) => w.style == CowStyle.brown),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'API uses AWS stage prefix, distinct manage credential and invalidates cached label',
    () async {
      SharedPreferences.setMockInitialValues({
        'cowlog_cache:https://farm.example/prod/v1/dashboard': 'old',
      });
      final client = ApiClient(
        baseUrl: 'https://farm.example/prod',
        token: 'read',
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://farm.example/prod/v1/collars/device-A/number',
          );
          expect(request.method, 'PUT');
          expect(request.headers['Authorization'], 'Bearer manage');
          expect(jsonDecode(request.body), {
            'number': '0007',
            'expected_number': null,
          });
          return http.Response(
            jsonEncode({
              'device_id': 'device-A',
              'number': '0007',
              'saved_to': 'server',
            }),
            200,
          );
        }),
      );
      await client.setNumber(
        const Collar(deviceId: 'device-A'),
        '0007',
        'manage',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'cowlog_cache:https://farm.example/prod/v1/dashboard',
        ),
        isNull,
      );
    },
  );

  test(
    'No offline success or cached registry when writes and registry fetch fail',
    () async {
      final client = ApiClient(
        baseUrl: 'https://farm.example',
        token: 'read',
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      );
      await expectLater(client.collars(), throwsA(isA<SocketException>()));
      await expectLater(
        client.setNumber(const Collar(deviceId: 'device-A'), '0007', 'manage'),
        throwsA(isA<SocketException>()),
      );
      final conflict = ApiClient(
        baseUrl: 'https://farm.example',
        token: 'read',
        httpClient: MockClient((_) async => http.Response('', 409)),
      );
      await expectLater(
        conflict.setNumber(
          const Collar(deviceId: 'device-A'),
          '0007',
          'manage',
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
