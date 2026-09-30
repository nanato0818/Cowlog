import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../state/app_store.dart';
import 'dashboard_screen.dart';

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
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final history = await widget.store.history(widget.cow.id, _date);
      if (mounted) {
        setState(() {
          _history = history;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _history = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<List<LatLng>> get _segments {
    final history = _history;
    if (history == null) return [];
    final result = <List<LatLng>>[];
    var current = <LatLng>[];
    DateTime? previous;
    for (final item in history.measurements) {
      if (!item.hasUsableCoordinate) {
        if (current.length > 1) result.add(current);
        current = [];
        previous = null;
        continue;
      }
      if (previous != null &&
          item.measuredAt.difference(previous).inHours > 1) {
        if (current.length > 1) result.add(current);
        current = [];
      }
      current.add(LatLng(item.latitude!, item.longitude!));
      previous = item.measuredAt;
    }
    if (current.length > 1) result.add(current);
    return result;
  }

  double get _distanceKm {
    const distance = Distance();
    var meters = 0.0;
    for (final segment in _segments) {
      for (var index = 1; index < segment.length; index++) {
        meters += distance(segment[index - 1], segment[index]);
      }
    }
    return meters / 1000;
  }

  @override
  Widget build(BuildContext context) {
    final positions = _segments.expand((segment) => segment).toList();
    final valid =
        _history?.measurements
            .where((item) => item.coverageSeconds > 0)
            .toList() ??
        [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.cow.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _StatusLabel(status: widget.cow.status),
              const Spacer(),
              if (widget.cow.batteryPercent case final battery?)
                Text('電池 $battery%'),
            ],
          ),
          const SizedBox(height: 8),
          Text(widget.cow.reason),
          if (widget.cow.latestMeasuredAt case final measured?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '最後の測定: ${dateTimeLabel(measured)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '表示する日: ${FarmDate.format(_date)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _date = picked);
                    _load();
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: const Text('変更'),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                message,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          const SizedBox(height: 16),
          Text('移動経路', style: Theme.of(context).textTheme.titleLarge),
          if (positions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('この日の位置記録はありません'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text('参考移動距離: ${_distanceKm.toStringAsFixed(1)} km'),
            ),
            SizedBox(
              height: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: positions.first,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'jp.ac.yuge.cowlog',
                    ),
                    PolylineLayer(
                      polylines: [
                        for (final segment in _segments)
                          Polyline(
                            points: segment,
                            color: Colors.blue,
                            strokeWidth: 3,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: positions.last,
                          width: 44,
                          height: 44,
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '距離は測位点を結んだ概算です。精度が100mを超える点と、1時間を超える空白はつなぎません。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          Text('行動量の推移', style: Theme.of(context).textTheme.titleLarge),
          if (valid.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('この日の行動量記録はありません'),
            )
          else ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _ActivityPainter(
                  valid.map((item) => item.activityRatio).toList(),
                  Theme.of(context).colorScheme.primary,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Text(
              '活動率 = 動きがあった秒数 ÷ 測定できた秒数。測定できなかった時間は除外しています。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final CowStatus status;
  @override
  Widget build(BuildContext context) => Text(
    status.label,
    style: TextStyle(fontWeight: FontWeight.bold, color: statusColor(status)),
  );
}

class _ActivityPainter extends CustomPainter {
  const _ActivityPainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height - 22;
    final barWidth = math.max(2.0, size.width / values.length - 2);
    final paint = Paint()..color = color.withValues(alpha: .72);
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()..color = Colors.grey.shade400,
    );
    for (var i = 0; i < values.length; i++) {
      final height = (baseline - 8) * values[i].clamp(0, 1);
      canvas.drawRect(
        Rect.fromLTWH(
          i * (size.width / values.length),
          baseline - height,
          barWidth,
          height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
