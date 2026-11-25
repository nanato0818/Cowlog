import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models.dart';
import '../farm_map.dart';
import '../app_theme.dart';
import '../activity_summary.dart';
import '../widgets/activity_charts.dart';
import '../route_segments.dart';
import '../state/app_store.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';

String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.store, required this.cow});
  final AppStore store;
  final Cow cow;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late DateTime _date;
  CowHistory? _history;
  final Map<String, DailyActivity?> _summaries = {};
  bool _loading = true, _failed = false, _partial = false, _aerial = true;
  int _request = 0, _pointIndex = 0;
  List<DateTime> get _days {
    final today = farmToday();
    final end = _date.isBefore(today.subtract(const Duration(days: 6)))
        ? _date
        : today;
    return List.generate(7, (i) => end.subtract(Duration(days: 6 - i)));
  }

  @override
  void initState() {
    super.initState();
    _date = farmToday();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final request = ++_request, date = _date;
    final days = _days;
    setState(() {
      _loading = true;
      _failed = false;
      _partial = false;
    });
    final now = DateTime.now();
    try {
      final current = await widget.store.history(
        widget.cow.id,
        date,
        force: force,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _history = current;
        _summaries.removeWhere((k, _) => !days.any((d) => dayKey(d) == k));
        _pointIndex =
            (current.measurements.where((m) => m.hasUsableCoordinate).length -
                    1)
                .clamp(0, 1000000);
        _summaries[dayKey(date)] = DailyActivity.fromMeasurements(
          date,
          current.measurements,
          now: now,
        );
      });
      final results = await Future.wait(
        days.where((d) => dayKey(d) != dayKey(date)).map((day) async {
          try {
            final h = await widget.store.history(
              widget.cow.id,
              day,
              force: force,
            );
            return MapEntry(
              dayKey(day),
              DailyActivity.fromMeasurements(day, h.measurements, now: now),
            );
          } catch (_) {
            return MapEntry<String, DailyActivity?>(dayKey(day), null);
          }
        }),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _summaries.addEntries(results);
        _partial = results.any((r) => r.value == null);
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2025),
      lastDate: farmToday(),
    );
    if (date != null && mounted) {
      setState(() => _date = date);
      _load();
    }
  }

  double get _distanceKm {
    const distance = Distance();
    var meters = 0.0;
    for (final segment in routeSegments(_history?.measurements ?? [])) {
      for (var i = 1; i < segment.length; i++) {
        meters += distance(segment[i - 1], segment[i]);
      }
    }
    return meters / 1000;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final cow =
        widget.store.dashboard?.cows
            .where((c) => c.id == widget.cow.id)
            .firstOrNull ??
        widget.cow;
    final points =
        _history?.measurements.where((m) => m.hasUsableCoordinate).toList() ??
        <Measurement>[];
    final selected = points.isEmpty
        ? null
        : points[_pointIndex.clamp(0, points.length - 1)];
    final notice = widget.store.isOffline
        ? 'オフライン'
        : (_failed || _partial)
        ? '一部未取得'
        : null;
    const heading = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (widget.store.demoMode) const Center(child: DemoBadge()),
          IconButton(
            tooltip: '更新',
            onPressed: _loading ? null : () => _load(force: true),
            icon: const Icon(CupertinoIcons.arrow_clockwise, size: 24),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  cow.displayNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              if (cow.batteryPercent != null) ...[
                const Icon(
                  CupertinoIcons.battery_75_percent,
                  size: 19,
                  color: AppColors.muted,
                ),
                Text(
                  '${cow.batteryPercent}%',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              StatusLabel(
                text: cow.status.label,
                urgent:
                    cow.status == CowStatus.check ||
                    cow.status == CowStatus.unknown,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Pill(
                leading: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 16,
                    color: AppColors.ink,
                  ),
                ),
                label:
                    '${_date.year}.${_date.month.toString().padLeft(2, '0')}.${_date.day.toString().padLeft(2, '0')}',
                selected: false,
                onTap: _pickDate,
              ),
              const Spacer(),
              if (notice != null) NoticeBadge(text: notice),
            ],
          ),
          const SizedBox(height: 10),
          LiveCard(
            icon: CupertinoIcons.chart_pie_fill,
            title: '1日の内訳',
            child: ActivityRings(summary: _summaries[dayKey(_date)]),
          ),
          const SizedBox(height: 10),
          LiveCard(
            icon: CupertinoIcons.chart_bar_alt_fill,
            title: '日平均の活動率',
            child: DailyActivityBars(
              days: _days,
              summaries: _summaries,
              selected: _date,
              onSelect: (d) {
                if (dayKey(d) != dayKey(_date)) {
                  HapticFeedback.selectionClick();
                  setState(() => _date = d);
                  _load();
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 6, 8),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.map_pin_ellipse,
                        size: 16,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6),
                      const Text('経路', style: heading),
                      const SizedBox(width: 10),
                      Text(
                        points.isEmpty
                            ? '—'
                            : '約 ${_distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '全画面',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RouteMapScreen(
                              cow: cow,
                              history: _history,
                              demo: widget.store.demoMode,
                            ),
                          ),
                        ),
                        icon: const Icon(
                          CupertinoIcons.arrow_up_left_arrow_down_right,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 290,
                  child: RouteMapCanvas(
                    key: ValueKey('route-${_history?.date}'),
                    records: _history?.measurements ?? [],
                    selected: selected,
                    aerial: _aerial,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 18, 0),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _aerial = !_aerial),
                        child: Text(
                          _aerial ? '地図' : '航空写真',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        selected == null
                            ? '位置なし'
                            : dateTimeLabel(selected.measuredAt),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                if (points.length > 1)
                  Slider(
                    value: _pointIndex.clamp(0, points.length - 1).toDouble(),
                    min: 0,
                    max: (points.length - 1).toDouble(),
                    divisions: points.length - 1,
                    onChanged: (v) => setState(() => _pointIndex = v.round()),
                  )
                else
                  const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RouteMapCanvas extends StatelessWidget {
  const RouteMapCanvas({
    super.key,
    required this.records,
    required this.selected,
    required this.aerial,
    this.padding = const EdgeInsets.all(30),
  });
  final List<Measurement> records;
  final Measurement? selected;
  final bool aerial;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final points = records
        .where((m) => m.hasUsableCoordinate)
        .map((m) => LatLng(m.latitude!, m.longitude!))
        .toList();
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: FarmMap.center,
              maxZoom: 20,
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(
                  points.isEmpty ? FarmMap.boundary : points,
                ),
                padding: padding,
                maxZoom: 17,
              ),
            ),
            children: [
              FarmMap.tiles(aerial),
              FarmMap.outline(),
              PolylineLayer(
                polylines: [
                  for (final segment in routeSegments(records))
                    Polyline(
                      points: segment,
                      color: AppColors.accent,
                      strokeWidth: 4,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              if (selected?.gpsAccuracyM != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(selected!.latitude!, selected!.longitude!),
                      radius: selected!.gpsAccuracyM!,
                      useRadiusInMeter: true,
                      color: Colors.white.withValues(alpha: .14),
                      borderColor: Colors.white.withValues(alpha: .6),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (points.isNotEmpty)
                    Marker(
                      point: points.first,
                      width: 22,
                      height: 22,
                      child: const Icon(
                        CupertinoIcons.circle,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  if (selected != null)
                    Marker(
                      point: LatLng(selected!.latitude!, selected!.longitude!),
                      width: 26,
                      height: 26,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: AppColors.glow,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Positioned(right: 5, bottom: 5, child: MapCredit(aerial: aerial)),
      ],
    );
  }
}

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({
    super.key,
    required this.cow,
    required this.history,
    required this.demo,
  });
  final Cow cow;
  final CowHistory? history;
  final bool demo;
  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  bool _aerial = true;
  int? _index;
  @override
  Widget build(BuildContext context) {
    final records = widget.history?.measurements ?? [];
    final points = records.where((m) => m.hasUsableCoordinate).toList();
    final index = (_index ?? points.length - 1).clamp(
      0,
      points.isEmpty ? 0 : points.length - 1,
    );
    final selected = points.isEmpty ? null : points[index];
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RouteMapCanvas(
              records: records,
              selected: selected,
              aerial: _aerial,
              padding: const EdgeInsets.fromLTRB(32, 150, 32, 180),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  MapControl(
                    icon: CupertinoIcons.back,
                    label: '戻る',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Glass(
                    radius: 23,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.cow.displayNumber,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        if (widget.demo) ...[
                          const SizedBox(width: 8),
                          const DemoBadge(),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  MapControl(
                    icon: CupertinoIcons.layers_alt,
                    label: '地図切替',
                    onTap: () => setState(() => _aerial = !_aerial),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Glass(
                  radius: 26,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected == null
                              ? '位置なし'
                              : dateTimeLabel(selected.measuredAt),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        if (points.length > 1)
                          Slider(
                            value: index.toDouble(),
                            min: 0,
                            max: (points.length - 1).toDouble(),
                            divisions: points.length - 1,
                            onChanged: (v) =>
                                setState(() => _index = v.round()),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
