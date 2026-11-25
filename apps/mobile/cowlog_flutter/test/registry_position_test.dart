import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cowlog_flutter/main.dart';
import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/state/app_store.dart';

void main() {
  test(
    'API registry is variable length and preserves arbitrary string numbers',
    () {
      final dashboard = Dashboard.fromJson({
        'generated_at': '2026-10-19T00:00:00Z',
        'cows': List.generate(
          27,
          (i) => {
            'id': 'uuid-$i',
            'name': '牛 A-000$i',
            'device_id': i == 0 ? null : 'hardware-$i',
            'status': 'no_data',
            'reason': '測定待ち',
            'profile': {
              'herd_number': 'A-000$i',
              'individual_number': '0012345678',
              'breed': '未登録',
              'birth_date': '未登録',
            },
          },
        ),
      });
      expect(dashboard.cows.length, 27);
      expect(dashboard.cows.first.deviceId, isNull);
      expect(dashboard.cows.first.profile!.herdNumber, 'A-0000');
      expect(dashboard.cows.first.profile!.individualNumber, '0012345678');
    },
  );

  test('Map rejects impossible coordinates and does not invent accuracy', () {
    CowPosition p(double lat, double lon, {double? accuracy}) => CowPosition(
      latitude: lat,
      longitude: lon,
      measuredAt: DateTime.utc(2026, 10, 19),
      accuracyM: accuracy,
    );
    expect(p(34.26712, 133.20581).isUsable, isTrue);
    expect(p(34.26712, 133.20581).accuracyM, isNull);
    expect(p(91, 139).isUsable, isFalse);
    expect(p(35, double.nan).isUsable, isFalse);
    expect(p(35, 139, accuracy: -1).isUsable, isFalse);
    expect(p(35, 139, accuracy: 101).isUsable, isFalse);
    expect(p(35, 139).isStaleAt(DateTime.utc(2026, 10, 19, 0, 16)), isTrue);
  });

  testWidgets('New readings refresh the visible tab without navigating away', (
    tester,
  ) async {
    final full = DemoData.dashboard();
    final store = AppStore()..dashboard = full;
    await tester.pumpWidget(CowlogApp(store: store));
    await tester.tap(find.text('優先一覧'));
    await tester.pumpAndSettle();
    expect(find.text('8 / 8頭'), findsOneWidget);
    store.dashboard = Dashboard(
      generatedAt: DateTime.now(),
      cows: [full.cows.first],
    );
    store.notifyListeners();
    await tester.pump();
    expect(find.text('1 / 1頭'), findsOneWidget);
    expect(find.text('8 / 8頭'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Registry tab shows cow-collar relation without connection form',
    (tester) async {
      final store = AppStore()..dashboard = DemoData.dashboard();
      await tester.pumpWidget(CowlogApp(store: store));
      await tester.tap(find.text('首輪・番号'));
      await tester.pumpAndSettle();
      expect(find.text('8台の首輪'), findsOneWidget);
      expect(find.textContaining('首輪ID：sample-1'), findsOneWidget);
      expect(find.text('クラウド接続'), findsNothing);
      expect(find.text('接続設定'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
