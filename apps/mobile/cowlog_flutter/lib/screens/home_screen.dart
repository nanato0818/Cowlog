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
  const HomeScreen({super.key, required this.store, this.visit = 0});
  final AppStore store;
  final int visit;
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
    final refreshed = CowlogUi.isRefreshed(context);
    final cows = store.dashboard?.cows ?? const <Cow>[];
    if (cows.isEmpty) {
      return Material(
        color: refreshed ? AppColors.refreshCanvas : AppColors.background,
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
    final stageHeight = refreshed
        ? (height * .43).clamp(top + 224, top + 420)
        : (height * .46).clamp(320.0, 460.0);
    final notice = store.isOffline ? 'オフライン' : store.errorMessage;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final details = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onInk,
      ),
      onPressed: () => _open(cow),
      child: const Text('詳細を見る'),
    );
    return Material(
      color: refreshed ? AppColors.refreshCanvas : AppColors.background,
      child: Stack(
        children: [
          // 上半分：横スワイプで個体を切り替える。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: stageHeight,
            child: DecoratedBox(
              decoration: refreshed
                  ? const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -.12),
                        radius: .9,
                        colors: [AppColors.surface, AppColors.refreshStageEdge],
                      ),
                    )
                  : const BoxDecoration(
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
                  final offset = refreshed && reduceMotion
                      ? 0.0
                      : (i - _page).clamp(-1.0, 1.0);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _open(cows[i]),
                    child: Padding(
                      padding: refreshed
                          ? EdgeInsets.fromLTRB(20, top + 58, 20, 56)
                          : EdgeInsets.fromLTRB(24, top + 70, 24, 46),
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
                      duration: refreshed && reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        cow.displayNumber,
                        key: ValueKey(cow.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: refreshed ? 44 : 38,
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
              decoration: BoxDecoration(
                color: refreshed
                    ? AppColors.refreshCanvas
                    : AppColors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: AppColors.cardShadow,
              ),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  refreshed ? 18 : 14,
                  14,
                  refreshed ? 18 : 14,
                  130,
                ),
                children: [
                  _MeasurementInfo(
                    cow: cow,
                    loading: _loading || _cowId != cow.id,
                  ),
                  SizedBox(height: refreshed ? 14 : 10),
                  LiveCard(
                    icon: CupertinoIcons.chart_pie_fill,
                    title: '今日の活動バランス',
                    child: ActivityRings(
                      summary: _cowId == cow.id
                          ? _summaries[dayKey(farmToday())]
                          : null,
                      revealKey: (widget.visit, cow.id),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DistanceCard(
                    key: ValueKey(cow.id),
                    distanceKm: _cowId == cow.id ? _distanceKm : null,
                  ),
                  if (refreshed) ...[const SizedBox(height: 12), details],
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
                  if (!refreshed) ...[const SizedBox(height: 16), details],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementInfo extends StatelessWidget {
  const _MeasurementInfo({required this.cow, required this.loading});

  final Cow cow;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final measured = cow.latestMeasuredAt;
    final battery = cow.batteryPercent;
    final low = battery != null && battery <= 30;
    final batteryColor = low ? AppColors.accentDark : AppColors.muted;
    final batteryLabel = battery == null ? '—' : '$battery%';
    const infoStyle = TextStyle(
      fontSize: 13,
      color: AppColors.muted,
      fontFeatures: tabularFigures,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                measured == null ? '未受信' : '最終計測 ${dateTimeLabel(measured)}',
                style: infoStyle,
              ),
              Semantics(
                label: battery == null ? '電池残量 不明' : '電池残量 $batteryLabel',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BatteryIcon(percent: battery, color: batteryColor),
                    const SizedBox(width: 5),
                    Text(
                      batteryLabel,
                      style: infoStyle.copyWith(
                        color: batteryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: '活動データ読み込み中',
            ),
          ),
      ],
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  const _BatteryIcon({required this.percent, required this.color});

  final int? percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = ((percent ?? 0) / 100).clamp(0.0, 1.0);
    return SizedBox(
      width: 22,
      height: 12,
      child: Stack(
        children: [
          Positioned.fill(
            right: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (fill > 0)
            Positioned(
              left: 2,
              top: 2,
              bottom: 2,
              width: 15 * fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          Positioned(
            right: 0,
            top: 4,
            bottom: 4,
            width: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistanceCard extends StatelessWidget {
  const _DistanceCard({super.key, required this.distanceKm});

  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final distance = distanceKm;
    final target = distance == null ? 0.0 : (distance / 4).clamp(0.0, 1.0);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LiveCard(
      title: '今日の移動距離',
      trailing: Text(
        distance == null ? '—' : '${distance.toStringAsFixed(1)} km',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFeatures: tabularFigures,
          color: AppColors.ink,
        ),
      ),
      child: ExcludeSemantics(
        child: SizedBox(
          height: 34,
          child: LayoutBuilder(
            builder: (context, box) {
              const markerSize = 24.0;
              final trackWidth = (box.maxWidth - markerSize).clamp(
                0.0,
                box.maxWidth,
              );
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? target : 0, end: target),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) => Stack(
                  children: [
                    Positioned(
                      left: markerSize / 2,
                      right: markerSize / 2,
                      bottom: 2,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.ringTrack,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    if (distance != null) ...[
                      Positioned(
                        left: markerSize / 2,
                        bottom: 2,
                        width: trackWidth * progress,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      Positioned(
                        left: trackWidth * progress,
                        top: 1,
                        child: const Icon(
                          Icons.directions_walk_rounded,
                          size: markerSize,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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
