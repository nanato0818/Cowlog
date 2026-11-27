import 'package:cowlog_flutter/app_theme.dart';
import 'package:cowlog_flutter/widgets/liquid_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _label = '航空写真';
final _switch = find.byType(LiquidSwitch);
final _lens = find.byType(RawMagnifier);

Future<void> _mountSwitch(
  WidgetTester tester,
  List<bool> changes, {
  bool reduceMotion = false,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  var value = false;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => LiquidSwitch(
                  label: _label,
                  value: value,
                  onChanged: (next) {
                    changes.add(next);
                    setState(() => value = next);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _trackWithColor(Color color) => find.descendant(
  of: _switch,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is ShapeDecoration &&
        (widget.decoration as ShapeDecoration).color == color,
  ),
);

void main() {
  testWidgets('tap and the accessibility action toggle one labeled switch', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <bool>[];
    await _mountSwitch(tester, changes);

    final switchSemantics = find.bySemanticsLabel(_label);
    expect(switchSemantics, findsOneWidget);
    expect(
      tester.getSemantics(switchSemantics),
      isSemantics(label: _label, hasToggledState: true, hasTapAction: true),
    );
    expect(tester.getSize(_switch).height, greaterThanOrEqualTo(44));
    expect(_trackWithColor(AppColors.switchOff), findsOneWidget);

    await tester.tap(find.text(_label));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(_trackWithColor(AppColors.accent), findsOneWidget);
    expect(
      tester.getSemantics(switchSemantics),
      isSemantics(
        label: _label,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );

    tester.semantics.tap(find.semantics.byLabel(_label));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    semantics.dispose();
  });

  testWidgets('held lens follows a drag and commits only on release', (
    tester,
  ) async {
    final changes = <bool>[];
    await _mountSwitch(tester, changes);

    final switchBounds = tester.getRect(_switch);
    final gesture = await tester.startGesture(
      switchBounds.centerRight - const Offset(46, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_lens, findsOneWidget);
    final start = tester.getCenter(_lens).dx;
    final initialWidth = tester.getSize(_lens).width;

    await gesture.moveBy(const Offset(19, 0));
    await tester.pump();
    expect(tester.getCenter(_lens).dx, greaterThan(start));
    expect(tester.getSize(_lens).width, greaterThan(initialWidth));
    expect(changes, isEmpty);

    await gesture.moveBy(const Offset(12, 0));
    await gesture.up();
    await tester.pump();
    expect(changes, [true]);
    expect(_lens, findsOneWidget);
    await tester.pumpAndSettle();
    expect(_lens, findsNothing);
    expect(_trackWithColor(AppColors.accent), findsOneWidget);

    await tester.drag(_switch, const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
  });

  testWidgets('a cancelled drag returns to the committed value', (
    tester,
  ) async {
    final changes = <bool>[];
    await _mountSwitch(tester, changes);
    final gesture = await tester.startGesture(tester.getCenter(_switch));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(_lens, findsNothing);
    expect(_trackWithColor(AppColors.switchOff), findsOneWidget);
  });

  testWidgets('Reduce Motion commits taps and drags without animation', (
    tester,
  ) async {
    final changes = <bool>[];
    await _mountSwitch(tester, changes, reduceMotion: true);

    final gesture = await tester.startGesture(tester.getCenter(_switch));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(_lens, findsNothing);
    expect(_trackWithColor(AppColors.switchOff), findsOneWidget);
    expect(changes, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(changes, [true]);
    expect(_trackWithColor(AppColors.accent), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tap(_switch);
    await tester.pump();
    expect(changes, [true, false]);
    expect(_lens, findsNothing);
    expect(_trackWithColor(AppColors.switchOff), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('drag direction follows right-to-left layout', (tester) async {
    final changes = <bool>[];
    await _mountSwitch(tester, changes, textDirection: TextDirection.rtl);
    await tester.drag(_switch, const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(changes, [true]);

    await tester.drag(_switch, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
  });
}
