import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_theme.dart';
import '../widgets/liquid_switch.dart';
import '../activity_summary.dart';
import '../route_segments.dart';
import '../state/app_store.dart';
import '../farm_map.dart';
import '../models.dart';
import 'detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final bool _aerial = true;
  final _controller = MapController();
  bool _routeMode = false;
  bool _routeLoading = false;
  bool _routeFailed = false;
  int _routeToken = 0;
  final Map<String, List<List<LatLng>>> _routes = {};

  Future<void> _toggleRoutes() async {
    HapticFeedback.selectionClick();
    if (_routeMode) {
      _routeToken++;
      setState(() {
        _routeMode = false;
        _routeLoading = false;
        _routeFailed = false;
        _routes.clear();
      });
      return;
    }
    final token = ++_routeToken;
    setState(() {
      _routeMode = true;
      _routeLoading = true;
      _routeFailed = false;
      _routes.clear();
    });
    final cows = widget.store.dashboard?.cows ?? <Cow>[];
    final today = farmToday();
    final results = await Future.wait(
      cows.map((cow) async {
        try {
          final h = await widget.store.history(cow.id, today);
          return MapEntry(cow.id, routeSegments(h.measurements));
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted || token != _routeToken) return;
    final ok = results.whereType<MapEntry<String, List<List<LatLng>>>>();
    final points = [
      for (final e in ok)
        for (final seg in e.value) ...seg,
    ];
    setState(() {
      _routeLoading = false;
      _routeFailed = cows.isNotEmpty && ok.isEmpty;
      _routes
        ..clear()
        ..addEntries(ok);
    });
    if (points.isNotEmpty) {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([...FarmMap.boundary, ...points]),
          padding: const EdgeInsets.fromLTRB(26, 110, 26, 190),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    final now = DateTime.now();
    final cows =
        store.dashboard?.cows
            .where((c) => c.latestPosition?.isUsable ?? false)
            .toList() ??
        <Cow>[];
    bool urgent(Cow c) =>
        c.status == CowStatus.check || c.status == CowStatus.unknown;
    // 要確認の牛を最後に描き、重なっても上に出す。
    final drawOrder = [...cows.where((c) => !urgent(c)), ...cows.where(urgent)];
    final notice = store.isOffline
        ? 'オフライン'
        : store.errorMessage ?? (_routeFailed ? '経路を取得できません' : null);
    final allCows = store.dashboard?.cows ?? <Cow>[];
    final lines = <Polyline>[];
    final hullPoints = <LatLng>[];
    if (_routeMode) {
      for (var i = 0; i < allCows.length; i++) {
        final segs = _routes[allCows[i].id];
        if (segs == null) continue;
        final color = routeColor(i).withValues(alpha: .85);
        for (final seg in segs) {
          hullPoints.addAll(seg);
          lines.add(
            Polyline(
              points: seg,
              strokeWidth: 3,
              color: color,
              borderStrokeWidth: 1,
              borderColor: Colors.white,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
        }
      }
    }
    final hull = convexHull(hullPoints);
    // extendBody のため、下部ナビの高さが padding.bottom に入る。
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: AppColors.background,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: FarmMap.center,
                  initialZoom: 16,
                  maxZoom: 20,
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([
                      ...FarmMap.boundary,
                      for (final cow in cows)
                        LatLng(
                          cow.latestPosition!.latitude,
                          cow.latestPosition!.longitude,
                        ),
                    ]),
                    padding: const EdgeInsets.fromLTRB(26, 110, 26, 190),
                    maxZoom: 17,
                  ),
                ),
                children: [
                  FarmMap.tiles(_aerial),
                  FarmMap.outline(),
                  if (hull.length >= 3)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: hull,
                          color: AppColors.accent.withValues(alpha: .10),
                          borderColor: AppColors.accent.withValues(alpha: .5),
                          borderStrokeWidth: 1,
                        ),
                      ],
                    ),
                  if (lines.isNotEmpty) PolylineLayer(polylines: lines),
                  CircleLayer(
                    circles: [
                      for (final cow in cows)
                        if (!_routeMode &&
                            cow.latestPosition!.accuracyM != null)
                          CircleMarker(
                            point: LatLng(
                              cow.latestPosition!.latitude,
                              cow.latestPosition!.longitude,
                            ),
                            radius: cow.latestPosition!.accuracyM!,
                            useRadiusInMeter: true,
                            color: Colors.white.withValues(alpha: .14),
                            borderColor: Colors.white.withValues(alpha: .55),
                            borderStrokeWidth: 1,
                          ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final cow in drawOrder)
                        Marker(
                          point: LatLng(
                            cow.latestPosition!.latitude,
                            cow.latestPosition!.longitude,
                          ),
                          width: urgent(cow) ? 84 : 44,
                          height: urgent(cow) ? 84 : 44,
                          child: Semantics(
                            button: true,
                            label: cow.displayNumber,
                            child: GestureDetector(
                              key: ValueKey('map-cow-${cow.id}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _open(cow),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  _Dot(
                                    stale: cow.latestPosition!.isStaleAt(now),
                                    urgent: urgent(cow),
                                  ),
                                  if (urgent(cow))
                                    Positioned(
                                      top: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.night,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 64,
                                          ),
                                          child: Text(
                                            cow.displayNumber,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.onInk,
                                              fontWeight: FontWeight.w700,
                                              fontFeatures: tabularFigures,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (store.demoMode || notice != null)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: notice != null
                        ? NoticeBadge(text: notice)
                        : const DemoBadge(),
                  ),
                ),
              ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(refreshed ? 116 : 18, 10, 18, 0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      LiquidSwitch(
                        label: '全頭の経路',
                        value: _routeMode,
                        onChanged: (_) => _toggleRoutes(),
                        onImagery: true,
                      ),
                      if (_routeLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                              semanticsLabel: '経路を読み込み中',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (cows.isNotEmpty)
              Positioned(
                left: refreshed ? 18 : 28,
                right: refreshed ? 18 : 28,
                bottom: bottom + (refreshed ? 12 : 8),
                child: SizedBox(
                  key: const ValueKey('map-cow-selector'),
                  height: refreshed ? 52 : 48,
                  child: Glass(
                    radius: refreshed ? 26 : 24,
                    tinted: refreshed,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: cows.length,
                      itemBuilder: (context, i) => InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _open(cows[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: urgent(cows[i])
                                      ? AppColors.ink
                                      : cows[i].latestPosition!.isStaleAt(now)
                                      ? const Color(0xff9a9a9e)
                                      : AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                cows[i].displayNumber,
                                style: TextStyle(
                                  fontWeight: refreshed
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: refreshed ? 16 : 15,
                                  color: AppColors.ink,
                                  fontFeatures: tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 牛ごとの経路色。accent を基準に明度・彩度・色相を少しずつ変える。
Color routeColor(int index) {
  final base = HSLColor.fromColor(AppColors.accent);
  final t = (index * 0.618034) % 1;
  final u = (index * 0.381966 + .2) % 1;
  return base
      .withHue((base.hue + (t - .5) * 28 + 360) % 360)
      .withSaturation((base.saturation * (.6 + .4 * u)).clamp(0.0, 1.0))
      .withLightness((.28 + .40 * t).clamp(0.0, 1.0))
      .toColor();
}

/// 凸包（monotone chain）。3点未満なら空。
List<LatLng> convexHull(List<LatLng> input) {
  final pts = {for (final p in input) (p.longitude, p.latitude)}.toList()
    ..sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );
  if (pts.length < 3) return const [];
  double cross((double, double) o, (double, double) a, (double, double) b) =>
      (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
  final lower = <(double, double)>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <(double, double)>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  final hull = [...lower, ...upper];
  if (hull.length < 3) return const [];
  return [for (final p in hull) LatLng(p.$2, p.$1)];
}

class _Dot extends StatelessWidget {
  const _Dot({required this.stale, required this.urgent});
  final bool stale, urgent;
  @override
  Widget build(BuildContext context) => Container(
    width: urgent ? 20 : 16,
    height: urgent ? 20 : 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: stale ? const Color(0xff9a9a9e) : null,
      gradient: stale ? null : AppColors.glow,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
    ),
  );
}

class MapControl extends StatelessWidget {
  const MapControl({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GlassButton(
    tooltip: label,
    onTap: onTap,
    radius: 23,
    size: const Size(46, 46),
    child: Icon(icon, size: 22, color: AppColors.ink),
  );
}

class MapCredit extends StatelessWidget {
  const MapCredit({super.key, required this.aerial});
  final bool aerial;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      aerial ? '出典：国土地理院' : '© OpenStreetMap contributors',
      style: const TextStyle(fontSize: 10, color: AppColors.night),
    ),
  );
}
