import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../state/app_store.dart';
import 'dashboard_screen.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final cows =
        store.dashboard?.cows
            .where((cow) => cow.latestPosition != null)
            .toList() ??
        [];
    if (cows.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('地図')),
        body: const Center(child: Text('位置情報がありません')),
      );
    }
    final first = cows.first.latestPosition!;
    return Scaffold(
      appBar: AppBar(title: const Text('地図')),
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(first.latitude, first.longitude),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'jp.ac.yuge.cowlog',
                ),
                MarkerLayer(
                  markers: [
                    for (final cow in cows)
                      Marker(
                        point: LatLng(
                          cow.latestPosition!.latitude,
                          cow.latestPosition!.longitude,
                        ),
                        width: 74,
                        height: 52,
                        child: Column(
                          children: [
                            Icon(
                              Icons.location_pin,
                              size: 34,
                              color: statusColor(cow.status),
                            ),
                            Text(
                              cow.name,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: Card(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .38,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (store.demoMode)
                            const Text(
                              'サンプルデータ',
                              style: TextStyle(color: Colors.blue),
                            ),
                          for (final cow in cows)
                            Text(
                              '${cow.name}　${dateTimeLabel(cow.latestPosition!.measuredAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'ピンは最後に測位できた場所です。現在地とは限りません。',
                            style: Theme.of(context).textTheme.bodySmall,
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
      ),
    );
  }
}
