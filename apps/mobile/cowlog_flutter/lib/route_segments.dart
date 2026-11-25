import 'package:latlong2/latlong.dart';
import 'models.dart';

List<List<LatLng>> routeSegments(List<Measurement> measurements) {
  final sorted = List<Measurement>.of(measurements)
    ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  final segments = <List<LatLng>>[];
  var current = <LatLng>[];
  DateTime? previous;
  void finish() {
    if (current.length > 1) segments.add(current);
    current = [];
  }

  for (final item in sorted) {
    if (!item.hasUsableCoordinate) {
      finish();
      previous = null;
      continue;
    }
    if (previous != null &&
        item.measuredAt.difference(previous) > const Duration(hours: 1)) {
      finish();
    }
    current.add(LatLng(item.latitude!, item.longitude!));
    previous = item.measuredAt;
  }
  finish();
  return segments;
}
