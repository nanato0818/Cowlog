import 'dart:math' as math;

import 'package:cowlog_flutter/app_theme.dart';
import 'package:cowlog_flutter/main.dart';
import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/screens/dashboard_screen.dart';
import 'package:cowlog_flutter/screens/detail_screen.dart';
import 'package:cowlog_flutter/screens/home_screen.dart';
import 'package:cowlog_flutter/screens/root_screen.dart';
import 'package:cowlog_flutter/state/app_store.dart';
import 'package:cowlog_flutter/widgets/activity_charts.dart';
import 'package:cowlog_flutter/widgets/liquid_switch.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Cowlog shows its main navigation', (tester) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));

    expect(find.text('優先一覧'), findsOneWidget);
    expect(find.text('地図'), findsOneWidget);
    expect(find.text('首輪・番号'), findsOneWidget);
    expect(find.text('設定'), findsNothing);
  });

  testWidgets('refreshed layout keeps the main flows usable on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore()..dashboard = DemoData.dashboard();
    await tester.pumpWidget(CowlogApp(store: store, refreshUi: true));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityRings), findsOneWidget);
    expect(find.textContaining('最終計測'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.gear_alt), findsOneWidget);

    final navigation = find.byKey(const ValueKey('app-navigation'));
    Future<void> openTab(String label) async {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text(label)),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('優先一覧')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byKey(const ValueKey('lens-trail')), findsOneWidget);
    expect(
      tester.widget<RawMagnifier>(find.byType(RawMagnifier)).size.height,
      greaterThan(tester.getSize(navigation).height),
    );
    await tester.pumpAndSettle();
    final toggle = find.byType(LiquidSwitch);
    expect(tester.widget<LiquidSwitch>(toggle).label, '位置あり');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<LiquidSwitch>(toggle).value, isTrue);
    expect(find.byType(CowCard), findsWidgets);

    await openTab('地図');
    expect(tester.widget<LiquidSwitch>(toggle).label, '全頭の経路');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<LiquidSwitch>(toggle).value, isTrue);
    expect(find.byType(PolylineLayer), findsOneWidget);

    await openTab('設定');
    expect(find.text('首輪・番号'), findsOneWidget);
    await tester.tap(find.byTooltip('首輪を追加'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    await openTab('ホーム');
    final details = find.text('詳細を見る').hitTestable();
    await tester.scrollUntilVisible(
      details,
      180,
      scrollable: find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    expect(find.byIcon(Icons.directions_walk_rounded), findsOneWidget);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(DetailScreen), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.calendar));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      toggle,
      260,
      scrollable: find.descendant(
        of: find.byType(DetailScreen),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RouteMapCanvas>(find.byType(RouteMapCanvas)).aerial,
      isFalse,
    );

    final fullscreen = find.byTooltip('全画面');
    await tester.ensureVisible(fullscreen);
    await tester.tap(fullscreen);
    await tester.pumpAndSettle();
    expect(find.byType(RouteMapScreen), findsOneWidget);
    expect(find.byTooltip('地図に切り替え'), findsOneWidget);
    final routeNumber = find.descendant(
      of: find.byType(RouteMapScreen),
      matching: find.text(store.dashboard!.cows.first.displayNumber),
    );
    expect(
      tester.renderObject<RenderParagraph>(routeNumber).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'refreshed status filters fit a narrow layout at large text sizes',
    (tester) async {
      tester.view
        ..physicalSize = const Size(320, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore()..dashboard = DemoData.dashboard();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => CowlogUi(
            refreshed: true,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
          home: DashboardScreen(store: store),
        ),
      );

      final filters = find.byKey(const ValueKey('dashboard-status-filters'));
      final pills = find.descendant(of: filters, matching: find.byType(Pill));
      final bounds = tester.getRect(filters).inflate(.01);
      for (final element in pills.evaluate()) {
        final pill = tester.getRect(find.byWidget(element.widget));
        expect(bounds.contains(pill.topLeft), isTrue);
        expect(bounds.contains(pill.bottomRight), isTrue);
      }
      final dataMissing = find.descendant(
        of: filters,
        matching: find.text('データ不足 1'),
      );
      expect(dataMissing, findsOneWidget);
      expect(
        tester.getTopLeft(dataMissing).dy,
        greaterThan(tester.getTopLeft(pills.first).dy),
      );
      await tester.tap(dataMissing);
      await tester.pumpAndSettle();
      expect(find.text('1 / 8頭'), findsOneWidget);
      expect(find.byType(CowCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  final nav = find.byKey(const ValueKey('app-navigation'));
  Finder tab(String label) =>
      find.descendant(of: nav, matching: find.text(label));

  testWidgets('The glass lens stretches on the way from home to collars', (
    tester,
  ) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));
    final target = tester.getCenter(tab('首輪・番号'));
    final start = tester.getCenter(tab('ホーム'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final glass = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
    final middle = tester.getCenter(find.byType(RawMagnifier));
    expect(glass.magnificationScale, greaterThan(1.15));
    expect(glass.size.height, greaterThan(tester.getSize(nav).height));
    expect(find.byKey(const ValueKey('lens-trail')), findsOneWidget);
    expect(middle.dx, greaterThan(start.dx));
    expect(middle.dx, lessThan(target.dx));

    await tester.pumpAndSettle();
    expect(find.byType(RawMagnifier), findsNothing);
    expect(find.byKey(const ValueKey('lens-trail')), findsNothing);
    expect(find.byKey(const ValueKey('tab-3')), findsOneWidget);
  });

  testWidgets('Switching back mid-flight keeps the glass lens in place', (
    tester,
  ) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));
    await tester.tap(tab('首輪・番号'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 95));
    final lens = find.byType(RawMagnifier);
    final before = tester.getRect(lens);

    await tester.tap(tab('ホーム'));
    await tester.pump();
    expect(tester.getRect(lens).center.dx, closeTo(before.center.dx, 1));
    await tester.pumpAndSettle();
    expect(lens, findsNothing);
    final home = tester.widget<Offstage>(find.byKey(const ValueKey('tab-0')));
    expect(home.offstage, isFalse);
  });

  testWidgets('Cancelling a tab drag settles the lens on the current page', (
    tester,
  ) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));
    final drag = await tester.startGesture(tester.getCenter(tab('ホーム')));
    await drag.moveBy(const Offset(50, 0));
    await drag.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(RawMagnifier), findsOneWidget);

    await drag.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(RawMagnifier), findsNothing);
    expect(find.byKey(const ValueKey('tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-1')), findsNothing);
  });

  testWidgets(
    'Reduced motion keeps tab selection instant at large text sizes',
    (tester) async {
      tester.view
        ..physicalSize = const Size(320, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: RootScreen(store: AppStore()),
        ),
      );
      final point = tester.getCenter(tab('首輪・番号'));
      final gesture = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 70));
      expect(find.byType(RawMagnifier), findsNothing);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('tab-3')), findsOneWidget);
      final home = tester.widget<Offstage>(find.byKey(const ValueKey('tab-0')));
      expect(home.offstage, isTrue);
      final pageFilter = tester.widget<ImageFiltered>(
        find
            .descendant(
              of: find.byKey(const ValueKey('tab-3')),
              matching: find.byType(ImageFiltered),
            )
            .first,
      );
      expect(pageFilter.enabled, isFalse);
      expect(find.byType(RawMagnifier), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Tab transitions blur both pages until the new page settles', (
    tester,
  ) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));

    ImageFiltered content(int index) => tester.widget<ImageFiltered>(
      find
          .descendant(
            of: find.byKey(ValueKey('tab-$index')),
            matching: find.byType(ImageFiltered),
          )
          .first,
    );
    expect(content(0).enabled, isFalse);

    await tester.tap(tab('優先一覧'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(content(0).enabled, isTrue);
    expect(content(1).enabled, isTrue);

    await tester.pumpAndSettle();
    expect(content(1).enabled, isFalse);
  });

  testWidgets(
    'Home shows one activity rate, battery info and a distance marker',
    (tester) async {
      final store = _ActivityStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(CowlogApp(store: store));
      await tester.pumpAndSettle();

      expect(find.text('活動率'), findsOneWidget);
      expect(
        find.text('${store.dashboard!.cows.first.batteryPercent}%'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('今日の移動距離'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byIcon(Icons.directions_walk_rounded), findsOneWidget);
      expect(find.text('0.0 km'), findsOneWidget);
    },
  );

  testWidgets('Home sweeps both rings on first visit, cow change and return', (
    tester,
  ) async {
    final store = _ActivityStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(CowlogApp(store: store));
    await tester.pump();

    expect(_paintRings(tester), paintsExactlyCountTimes(#drawArc, 0));
    await tester.pump(const Duration(milliseconds: 130));
    expect(
      _paintRings(tester),
      paints
        ..something(
          (method, args) =>
              method == #drawArc && args[2] > 0 && args[2] < math.pi / 2,
        )
        ..something(
          (method, args) =>
              method == #drawArc && args[2] > 0 && args[2] < 3 * math.pi / 2,
        ),
    );
    await tester.pumpAndSettle();
    expect(
      _paintRings(tester),
      paints
        ..something(_sweepIs(math.pi / 2))
        ..something(_sweepIs(3 * math.pi / 2)),
    );

    await tester.drag(
      find.byKey(const ValueKey('home-pages')),
      const Offset(-600, 0),
    );
    await tester.pump();
    expect(_paintRings(tester), paintsExactlyCountTimes(#drawArc, 0));
    await tester.pumpAndSettle();
    expect(
      _paintRings(tester),
      paints
        ..something(_sweepIs(3 * math.pi / 2))
        ..something(_sweepIs(math.pi / 2)),
    );

    await tester.tap(tab('優先一覧'));
    await tester.pumpAndSettle();
    await tester.tap(tab('ホーム'));
    await tester.pump();
    expect(_paintRings(tester), paintsExactlyCountTimes(#drawArc, 0));
    await tester.pumpAndSettle();
    expect(
      _paintRings(tester),
      paints
        ..something(_sweepIs(3 * math.pi / 2))
        ..something(_sweepIs(math.pi / 2)),
    );
  });

  testWidgets('Home skips the ring sweep when motion is reduced', (
    tester,
  ) async {
    final store = _ActivityStore();
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
    await tester.pump();

    expect(
      _paintRings(tester),
      paints
        ..something(_sweepIs(math.pi / 2))
        ..something(_sweepIs(3 * math.pi / 2)),
    );
  });
}

PaintPatternPredicate _sweepIs(double expected) =>
    (method, args) =>
        method == #drawArc && ((args[2] as double) - expected).abs() < 1e-6;

void Function(Canvas) _paintRings(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(ActivityRings),
    matching: find.byType(CustomPaint),
  );
  final painter = tester.widget<CustomPaint>(finder).painter!;
  return (canvas) => painter.paint(canvas, const Size.square(160));
}

class _ActivityStore extends AppStore {
  _ActivityStore() {
    dashboard = DemoData.dashboard();
  }

  @override
  Future<CowHistory> history(
    String cowId,
    DateTime date, {
    bool force = false,
  }) async {
    final end = DateTime.utc(
      date.year,
      date.month,
      date.day + 1,
    ).subtract(const Duration(hours: 9));
    return CowHistory(
      cowId: cowId,
      date: FarmDate.format(date),
      measurements: [
        Measurement(
          measuredAt: end,
          activitySeconds: cowId == dashboard!.cows.first.id ? 21600 : 64800,
          coverageSeconds: 86400,
          intervalSeconds: 86400,
        ),
      ],
    );
  }
}
