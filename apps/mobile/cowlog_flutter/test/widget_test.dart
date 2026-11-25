import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cowlog_flutter/main.dart';
import 'package:cowlog_flutter/screens/root_screen.dart';
import 'package:cowlog_flutter/state/app_store.dart';

void main() {
  testWidgets('Cowlog shows its main navigation', (tester) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));

    expect(find.text('優先一覧'), findsOneWidget);
    expect(find.text('地図'), findsOneWidget);
    expect(find.text('接続設定'), findsOneWidget);
  });

  testWidgets('The tab lens stretches on its way from home to settings', (
    tester,
  ) async {
    final store = AppStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(CowlogApp(store: store));

    final lens = find.byKey(const ValueKey('tab-lens'));
    final start = tester.getRect(lens);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final middle = tester.getRect(lens);
    await tester.pumpAndSettle();
    final end = tester.getRect(lens);

    expect(middle.center.dx, greaterThan(start.center.dx));
    expect(middle.center.dx, lessThan(end.center.dx));
    expect(middle.width, greaterThan(start.width));
    expect(end.width, closeTo(start.width, 0.01));
    expect(find.text('サンプルデータを使う'), findsOneWidget);
  });

  testWidgets('Changing direction keeps the moving tab lens continuous', (
    tester,
  ) async {
    final store = AppStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(CowlogApp(store: store));

    final lens = find.byKey(const ValueKey('tab-lens'));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final before = tester.getRect(lens);

    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pump();
    final after = tester.getRect(lens);
    expect(after.center.dx, closeTo(before.center.dx, 0.01));
    expect(after.width, closeTo(before.width, 0.01));
    await tester.pumpAndSettle();
    expect(find.text('牛の状態'), findsOneWidget);
  });

  testWidgets('Reduced motion moves the tab lens directly to settings', (
    tester,
  ) async {
    final store = AppStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: RootScreen(store: store),
      ),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    final lens = find.byKey(const ValueKey('tab-lens'));
    final selection = find.byIcon(Icons.settings);
    expect(
      tester.getCenter(lens).dx,
      closeTo(tester.getCenter(selection).dx, 0.01),
    );
    expect(find.text('サンプルデータを使う'), findsOneWidget);
  });
}
