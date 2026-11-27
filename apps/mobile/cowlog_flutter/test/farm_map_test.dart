import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:cowlog_flutter/farm_map.dart';
import 'package:cowlog_flutter/state/app_store.dart';
import 'package:cowlog_flutter/screens/map_screen.dart';
import 'package:cowlog_flutter/models.dart';
import 'package:cowlog_flutter/widgets/liquid_switch.dart';

bool inside(List<LatLng> b, LatLng p) {
  bool result = false;
  for (int i = 0, j = b.length - 1; i < b.length; j = i++) {
    if ((b[i].latitude > p.latitude) != (b[j].latitude > p.latitude) &&
        p.longitude <
            (b[j].longitude - b[i].longitude) *
                    (p.latitude - b[i].latitude) /
                    (b[j].latitude - b[i].latitude) +
                b[i].longitude) {
      result = !result;
    }
  }
  return result;
}

void main() {
  test('Daigo boundary is restored and demonstration routes stay inside', () {
    expect(FarmMap.areas.length, 5);
    expect(FarmMap.areas.map((a) => a.use), [
      '放牧地',
      '放牧地',
      '採草地',
      '採草地',
      '採草地',
    ]);
    expect(FarmMap.outline().polygons.length, 5);
    for (final area in FarmMap.areas) {
      expect(inside(area.points, area.labelPosition), isTrue);
    }
    for (var c = 0; c < 8; c++) {
      for (var t = 0; t < 288; t++) {
        final p = DemoData.coordinate(c, t);
        expect(
          inside(FarmMap.areas.first.points, LatLng(p.$1, p.$2)),
          isTrue,
          reason: 'cow $c, step $t',
        );
      }
    }
  });
  testWidgets('Aerial map keeps its route switch visible without GPS', (
    tester,
  ) async {
    final store = AppStore()
      ..dashboard = Dashboard(generatedAt: DateTime.now(), cows: []);
    await tester.pumpWidget(MaterialApp(home: MapScreen(store: store)));
    expect(find.text('Cowlog'), findsNothing);
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      contains('seamlessphoto'),
    );
    expect(find.byType(PolygonLayer), findsOneWidget);
    final routeSwitch = find.byType(LiquidSwitch);
    expect(routeSwitch, findsOneWidget);
    expect(tester.widget<LiquidSwitch>(routeSwitch).label, '全頭の経路');
    expect(tester.widget<LiquidSwitch>(routeSwitch).value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
