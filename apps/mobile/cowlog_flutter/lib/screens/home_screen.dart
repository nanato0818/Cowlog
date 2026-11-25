import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../activity_summary.dart';
import '../app_theme.dart';
import '../models.dart';
import '../route_segments.dart';
import '../state/app_store.dart';
import '../widgets/activity_charts.dart';
import '../widgets/cow_model_view.dart';
import 'dashboard_screen.dart';
import 'detail_screen.dart';

/// ホーム：上半分は1頭ずつ横スワイプで切り替え、下半分はその牛の状態。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pages = PageController();
  double _page = 0;
  int _index = 0;
  String? _cowId;
  int _request = 0;
  bool _loading = false;
  final Map<String, DailyActivity?> _summaries = {};
  double? _distanceKm;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() => setState(() => _page = _pages.page ?? 0));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<DateTime> get _days {
    final today = farmToday();
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  Future<void> _load(Cow cow) async {
    final request = ++_request;
    final days = _days;
    final now = DateTime.now();
    setState(() {
      _cowId = cow.id;
      _loading = true;
      _summaries.clear();
      _distanceKm = null;
    });
    final results = await Future.wait(
      days.map((day) async {
        try {
          return (day, await widget.store.history(cow.id, day));
        } catch (_) {
          return (day, null);
        }
      }),
    );
    if (!mounted || request != _request) return;
    setState(() {
      for (final (day, history) in results) {
        _summaries[dayKey(day)] = history == null
            ? null
            : DailyActivity.fromMeasurements(
                day,
                history.measurements,
                now: now,
              );
      }
      final today = results.last.$2;
      if (today != null) {
        const distance = Distance();
        var meters = 0.0;
        for (final segment in routeSegments(today.measurements)) {
          for (var i = 1; i < segment.length; i++) {
            meters += distance(segment[i - 1], segment[i]);
          }
        }
        _distanceKm = meters / 1000;
      }
      _loading = false;
    });
  }

  void _open(Cow cow) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DetailScreen(store: widget.store, cow: cow),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final store = widget.store;
    final cows = store.dashboard?.cows ?? const <Cow>[];
    if (cows.isEmpty) {
      return Material(
        color: AppColors.background,
        child: Center(
          child: store.isLoading
              ? const CircularProgressIndicator()
              : const Text(
                  '該当なし',
                  style: TextStyle(fontSize: 15, color: AppColors.muted),
                ),
        ),
      );
    }
    final index = _index.clamp(0, cows.length - 1);
    final cow = cows[index];
    if (_cowId != cow.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cowId != cow.id) _load(cow);
      });
    }
    final height = MediaQuery.sizeOf(context).height;
    final top = MediaQuery.paddingOf(context).top;
    final stageHeight = (height * .46).clamp(320.0, 460.0);
    final notice = store.isOffline ? 'オフライン' : store.errorMessage;
    return Material(
      color: AppColors.background,
      child: Stack(
        children: [
          // 上半分：横スワイプで個体を切り替える。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: stageHeight,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.stageTop, AppColors.stageBottom],
                ),
              ),
              child: PageView.builder(
                key: const ValueKey('home-pages'),
                controller: _pages,
                itemCount: cows.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _index = i);
                },
                itemBuilder: (context, i) {
                  final offset = (i - _page).clamp(-1.0, 1.0);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _open(cows[i]),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, top + 70, 24, 46),
                      child: Opacity(
                        opacity: 1 - offset.abs() * .5,
                        child: Transform.translate(
                          // 牛は背景より少しゆっくり動かし、奥行きを出す。
                          offset: Offset(offset * 60, 0),
                          child: Transform.scale(
                            scale: 1 - offset.abs() * .12,
                            child: CowModelView(style: cows[i].style),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 上部の番号と状態。
          Positioned(
            left: 20,
            right: 20,
            top: top + 10,
            child: IgnorePointer(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        cow.displayNumber,
                        key: ValueKey(cow.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          fontFeatures: tabularFigures,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  if (notice != null) ...[
                    NoticeBadge(text: notice),
                    const SizedBox(width: 8),
                  ] else if (store.demoMode) ...[
                    const DemoBadge(),
                    const SizedBox(width: 8),
                  ],
                  StatusLabel(
                    text: cow.status.label,
                    urgent:
                        cow.status == CowStatus.check ||
                        cow.status == CowStatus.unknown,
                  ),
                ],
              ),
            ),
          ),
          // ページの位置。
          Positioned(
            left: 0,
            right: 0,
            top: stageHeight - 64,
            child: Center(
              child: _PageDots(count: cows.length, page: _page),
            ),
          ),
          // 下半分：状態。
          Positioned.fill(
            top: stageHeight - 26,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: AppColors.cardShadow,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 130),
                children: [
                  _StatRow(
                    cow: cow,
                    today: _summaries[dayKey(farmToday())],
                    yesterday:
                        _summaries[dayKey(
                          farmToday().subtract(const Duration(days: 1)),
                        )],
                    distanceKm: _distanceKm,
                    loading: _loading,
                  ),
                  const SizedBox(height: 10),
                  LiveCard(
                    icon: CupertinoIcons.chart_pie_fill,
                    title: '今日の活動バランス',
                    child: ActivityRings(
                      summary: _summaries[dayKey(farmToday())],
                    ),
                  ),
                  const SizedBox(height: 10),
                  LiveCard(
                    icon: CupertinoIcons.chart_bar_alt_fill,
                    title: '直近7日の活動率',
                    child: DailyActivityBars(
                      days: _days,
                      summaries: _summaries,
                      selected: farmToday(),
                      onSelect: (_) => _open(cow),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _open(cow),
                    child: const Text('詳細を見る'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.cow,
    required this.today,
    required this.yesterday,
    required this.distanceKm,
    required this.loading,
  });
  final Cow cow;
  final DailyActivity? today, yesterday;
  final double? distanceKm;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final battery = cow.batteryPercent;
    final active = today?.activityRatio;
    final before = yesterday?.activityRatio;
    final measured = cow.latestMeasuredAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                icon: CupertinoIcons.battery_75_percent,
                label: '電池',
                gaugeColor: AppColors.gaugeBattery,
                value: battery?.toString(),
                unit: '%',
                ratio: battery == null ? null : battery / 100,
                low: battery != null && battery <= 30,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                icon: CupertinoIcons.waveform_path_ecg,
                label: '活動率',
                gaugeColor: AppColors.gaugeActivity,
                value: active == null ? null : '${(active * 100).round()}',
                unit: '%',
                ratio: active,
                foot: before == null ? null : '昨日 ${(before * 100).round()}%',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                icon: CupertinoIcons.location_solid,
                label: '移動距離',
                gaugeColor: AppColors.gaugeDistance,
                value: distanceKm?.toStringAsFixed(1),
                unit: 'km',
                ratio: distanceKm == null
                    ? null
                    : (distanceKm! / 4).clamp(0.0, 1.0),
                foot: '今日',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            measured == null ? '未受信' : '最終計測 ${dateTimeLabel(measured)}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.ratio,
    required this.gaugeColor,
    this.foot,
    this.low = false,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String unit;
  final double? ratio;
  final Color gaugeColor;
  final String? foot;
  final bool low;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(26),
      boxShadow: AppColors.cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: gaugeColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value ?? '—',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8,
                    color: low ? AppColors.accent : AppColors.ink,
                  ),
                ),
                if (value != null)
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: low ? AppColors.accent : AppColors.muted,
                    ),
                  ),
              ],
            ),
            style: const TextStyle(fontFeatures: tabularFigures),
          ),
        ),
        const SizedBox(height: 10),
        SegmentGauge(ratio: ratio, segments: 8, color: gaugeColor),
        const SizedBox(height: 8),
        Text(
          foot ?? ' ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.muted,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    ),
  );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.page});
  final int count;
  final double page;
  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    if (count > 12) {
      return Glass(
        radius: 14,
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          '${page.round() + 1} / $count',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
        ),
      );
    }
    return Glass(
      radius: 14,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Builder(
              builder: (context) {
                final near = (1 - (page - i).abs()).clamp(0.0, 1.0);
                return Container(
                  width: 6 + 12 * near,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Color.lerp(AppColors.faint, AppColors.accent, near),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
