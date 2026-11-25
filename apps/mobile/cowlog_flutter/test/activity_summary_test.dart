import 'package:flutter_test/flutter_test.dart';
import 'package:cowlog_flutter/activity_summary.dart';
import 'package:cowlog_flutter/models.dart';

Measurement m(
  DateTime end, {
  int interval = 7200,
  int coverage = 3600,
  int active = 1800,
}) => Measurement(
  measuredAt: end,
  intervalSeconds: interval,
  coverageSeconds: coverage,
  activitySeconds: active,
);
void main() {
  final date = DateTime(2026, 11, 9);
  final end = DateTime.utc(2026, 11, 8, 17); // 02:00 JST
  test(
    'Two rings use measured time only, excluding missing and future time',
    () {
      final s = DailyActivity.fromMeasurements(date, [m(end)], now: end);
      expect(s.elapsedSeconds, 7200);
      expect(s.activeSeconds, 1800);
      expect(s.inactiveSeconds, 1800);
      expect(s.unknownSeconds, 3600);
      expect(s.fractions, [.5, .5]);
      expect(s.activityRatio, .5);
    },
  );
  test('Overlaps and resends do not inflate daily measured time', () {
    final s = DailyActivity.fromMeasurements(date, [
      m(end),
      m(end),
      m(end.subtract(const Duration(hours: 1))),
    ], now: end);
    expect(s.coveredSeconds, 3600);
    expect(s.activeSeconds, 1800);
    expect(s.unknownSeconds, 3600);
  });
  test(
    'A crossing-midnight interval is apportioned to Japanese calendar day',
    () {
      final at = DateTime.utc(2026, 11, 8, 16); // 01:00 JST
      final s = DailyActivity.fromMeasurements(date, [
        m(at, coverage: 7200, active: 3600),
      ], now: at);
      expect(s.elapsedSeconds, 3600);
      expect(s.activeSeconds, 1800);
      expect(s.inactiveSeconds, 1800);
      expect(s.unknownSeconds, 0);
    },
  );
  test('Missing data differs from measured zero activity', () {
    final missing = DailyActivity.fromMeasurements(date, [], now: end);
    final still = DailyActivity.fromMeasurements(date, [
      m(end, coverage: 7200, active: 0),
    ], now: end);
    expect(missing.activityRatio, isNull);
    expect(missing.fractions, [0, 0]);
    expect(still.fractions, [0, 1]);
    expect(missing.unknownSeconds, 7200);
    expect(still.activityRatio, 0);
    expect(still.inactiveSeconds, 7200);
  });
  test(
    'Daily mean weights actual measured seconds, rather than averaging percentages',
    () {
      final s = DailyActivity.fromMeasurements(date, [
        m(
          end.subtract(const Duration(hours: 1)),
          interval: 3600,
          coverage: 3600,
          active: 1800,
        ),
        m(end, interval: 3600, coverage: 600, active: 0),
      ], now: end);
      expect(s.activityRatio, closeTo(1800 / 4200, 1e-9));
      expect(
        s.activeSeconds + s.inactiveSeconds + s.unknownSeconds,
        s.elapsedSeconds,
      );
    },
  );
}
