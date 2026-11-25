import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../activity_summary.dart';
import '../app_theme.dart';

const _ringColors = [AppColors.ringActive, AppColors.ringInactive];
const _ringLabels = ['活動', '非活動'];

class ActivityRings extends StatelessWidget {
  const ActivityRings({super.key, required this.summary});
  final DailyActivity? summary;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final diameter = math.min(210.0, box.maxWidth * .58);
      final values = summary == null
          ? <double>[]
          : [summary!.activeSeconds, summary!.inactiveSeconds];
      final ratio = summary?.activityRatio;
      return Semantics(
        label: summary == null || summary!.coveredSeconds == 0
            ? '行動量未取得'
            : [
                for (var i = 0; i < _ringLabels.length; i++)
                  '${_ringLabels[i]} ${activityDuration(values[i])}',
              ].join('、'),
        child: Row(
          children: [
            SizedBox(
              width: diameter,
              height: diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (summary?.fractions ?? [0, 0])[0]),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 520),
                      curve: Curves.easeOutCubic,
                      builder: (context, active, _) => CustomPaint(
                        painter: _RingPainter([
                          active,
                          summary == null || summary!.coveredSeconds == 0
                              ? 0
                              : 1 - active,
                        ]),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ratio == null ? '—' : '${(ratio * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 34,
                          fontFeatures: tabularFigures,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const Text(
                        '活動率',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _ringLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: _ringColors[i],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _ringLabels[i],
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary == null || summary!.coveredSeconds == 0
                                ? '—'
                                : activityDuration(values[i]),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fractions);
  final List<double> fractions;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.shortestSide * .07;
    final gap = stroke * .6;
    for (var i = 0; i < _ringLabels.length; i++) {
      final radius = size.shortestSide / 2 - stroke - i * (stroke + gap);
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, radius, paint..color = AppColors.ringTrack);
      final f = fractions[i].clamp(0.0, 1.0);
      if (f > 0) {
        paint.color = _ringColors[i];
        if (f >= .9999) {
          canvas.drawCircle(center, radius, paint);
        } else {
          canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fractions[0] != fractions[0] || old.fractions[1] != fractions[1];
}

class DailyActivityBars extends StatelessWidget {
  const DailyActivityBars({
    super.key,
    required this.days,
    required this.summaries,
    required this.selected,
    required this.onSelect,
  });
  final List<DateTime> days;
  final Map<String, DailyActivity?> summaries;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days)
          Expanded(
            child: Tooltip(
              message: summaries[_key(day)] == null
                  ? '未取得'
                  : '測定率 ${(summaries[_key(day)]!.coverageRatio * 100).round()}%',
              child: InkWell(
                onTap: () => onSelect(day),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text(
                        summaries[_key(day)]?.activityRatio == null
                            ? '—'
                            : '${(summaries[_key(day)]!.activityRatio! * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontFeatures: tabularFigures,
                          fontWeight: _key(day) == _key(selected)
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _key(day) == _key(selected)
                              ? AppColors.ink
                              : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final ratio = summaries[_key(day)]?.activityRatio;
                            return Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                Container(
                                  width: 12,
                                  decoration: BoxDecoration(
                                    color: AppColors.ringTrack,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                if (ratio != null)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 420),
                                    curve: Curves.easeOutCubic,
                                    key: ValueKey('daily-bar-${_key(day)}'),
                                    width: 12,
                                    height: math.max(
                                      12,
                                      box.maxHeight * ratio.clamp(0, 1),
                                    ),
                                    decoration: BoxDecoration(
                                      color: _key(day) == _key(selected)
                                          ? AppColors.accent
                                          : AppColors.barIdle,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${day.month}/${day.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontFeatures: tabularFigures,
                          fontWeight: _key(day) == _key(selected)
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _key(day) == _key(selected)
                              ? AppColors.ink
                              : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              summaries[_key(day)] != null &&
                                  summaries[_key(day)]!.coverageRatio < .7
                              ? AppColors.ink
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
