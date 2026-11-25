import 'dart:math' as math;
import 'models.dart';

/// Aggregates interval-end measurements into a Japanese calendar day.
/// A partial interval is apportioned by duration; no activity classification is inferred.
class DailyActivity {
  const DailyActivity({
    required this.date,
    required this.elapsedSeconds,
    required this.activeSeconds,
    required this.inactiveSeconds,
    required this.unknownSeconds,
  });
  final DateTime date;
  final double elapsedSeconds, activeSeconds, inactiveSeconds, unknownSeconds;
  double get coveredSeconds => activeSeconds + inactiveSeconds;
  double? get activityRatio =>
      coveredSeconds > 0 ? activeSeconds / coveredSeconds : null;
  double get coverageRatio =>
      elapsedSeconds == 0 ? 0 : coveredSeconds / elapsedSeconds;

  /// Only measured time contributes to the two activity rings.
  List<double> get fractions => coveredSeconds == 0
      ? [0, 0]
      : [activeSeconds / coveredSeconds, inactiveSeconds / coveredSeconds];

  factory DailyActivity.fromMeasurements(
    DateTime date,
    List<Measurement> records, {
    DateTime? now,
  }) {
    final start = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
    final end = math.min(
      start + const Duration(days: 1).inMilliseconds,
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
    );
    final elapsed = math.max(0, end - start) / 1000.0;
    if (elapsed == 0) {
      return DailyActivity(
        date: date,
        elapsedSeconds: 0,
        activeSeconds: 0,
        inactiveSeconds: 0,
        unknownSeconds: 0,
      );
    }
    final valid =
        records
            .where(
              (m) =>
                  m.intervalSeconds > 0 &&
                  m.activitySeconds >= 0 &&
                  m.coverageSeconds >= m.activitySeconds &&
                  m.coverageSeconds <= m.intervalSeconds &&
                  m.measuredAt.millisecondsSinceEpoch > start &&
                  m.measuredAt.millisecondsSinceEpoch -
                          m.intervalSeconds * 1000 <
                      end,
            )
            .toList()
          ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final cuts = <int>{start, end};
    for (final m in valid) {
      cuts.add(
        math.max(
          start,
          m.measuredAt.millisecondsSinceEpoch - m.intervalSeconds * 1000,
        ),
      );
      cuts.add(math.min(end, m.measuredAt.millisecondsSinceEpoch));
    }
    final sorted = cuts.toList()..sort();
    double active = 0, covered = 0;
    for (var i = 1; i < sorted.length; i++) {
      final a = sorted[i - 1], b = sorted[i];
      // Overlapping/repeated records do not count the same time twice.
      for (final m in valid) {
        final finish = m.measuredAt.millisecondsSinceEpoch;
        if (finish >= b && finish - m.intervalSeconds * 1000 <= a) {
          final seconds = (b - a) / 1000;
          active += seconds * m.activitySeconds / m.intervalSeconds;
          covered += seconds * m.coverageSeconds / m.intervalSeconds;
          break;
        }
      }
    }
    covered = covered.clamp(0, elapsed);
    active = active.clamp(0, covered);
    return DailyActivity(
      date: date,
      elapsedSeconds: elapsed,
      activeSeconds: active,
      inactiveSeconds: covered - active,
      unknownSeconds: elapsed - covered,
    );
  }
}

DateTime farmToday([DateTime? now]) {
  final jst = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return DateTime(jst.year, jst.month, jst.day);
}

String activityDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes分';
  return '${minutes ~/ 60}時間${minutes % 60 == 0 ? '' : '${minutes % 60}分'}';
}
