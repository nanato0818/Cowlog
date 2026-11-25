import 'package:cowlog_flutter/screens/map_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('convexHull drops interior points and needs 3 points', () {
    expect(convexHull([const LatLng(0, 0), const LatLng(1, 1)]), isEmpty);
    final hull = convexHull([
      const LatLng(0, 0),
      const LatLng(0, 2),
      const LatLng(2, 2),
      const LatLng(2, 0),
      const LatLng(1, 1),
    ]);
    expect(hull.length, 4);
    expect(hull.contains(const LatLng(1, 1)), isFalse);
  });
}
