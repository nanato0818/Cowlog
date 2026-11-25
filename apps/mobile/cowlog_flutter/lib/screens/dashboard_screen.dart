import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_store.dart';
import 'detail_screen.dart';

Color statusColor(CowStatus status) => switch (status) {
  CowStatus.check => Colors.orange.shade800,
  CowStatus.disconnected ||
  CowStatus.insufficient ||
  CowStatus.noData => Colors.grey.shade600,
  CowStatus.learning => Colors.blue.shade700,
  CowStatus.normal => Colors.green.shade700,
};

String dateTimeLabel(DateTime value) =>
    '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('牛の状態'),
      actions: [
        IconButton(
          onPressed: store.isLoading ? null : store.refresh,
          icon: const Icon(Icons.refresh),
          tooltip: '更新',
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (store.demoMode)
            const _Notice(
              text: 'サンプルデータを表示中',
              icon: Icons.info_outline,
              color: Colors.blue,
            ),
          if (store.errorMessage case final message?)
            _Notice(text: message, icon: Icons.wifi_off, color: Colors.orange),
          if (store.dashboard case final dashboard?) ...[
            Text(
              'データ更新: ${dateTimeLabel(dashboard.generatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final cow in dashboard.cows) ...[
              CowCard(
                cow: cow,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(store: store, cow: cow),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
          if ((store.dashboard?.cows.isEmpty ?? true) &&
              !store.isLoading &&
              store.errorMessage == null)
            const Padding(
              padding: EdgeInsets.only(top: 96),
              child: Center(child: Text('表示する牛がいません')),
            ),
          if (store.isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    ),
  );
}

class CowCard extends StatelessWidget {
  const CowCard({super.key, required this.cow, required this.onTap});
  final Cow cow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cow.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: cow.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(cow.reason),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  cow.latestMeasuredAt == null
                      ? '測定記録なし'
                      : '測定 ${dateTimeLabel(cow.latestMeasuredAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  cow.batteryPercent == null
                      ? '電池 不明'
                      : '電池 ${cow.batteryPercent}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  cow.latestPosition == null ? '位置記録なし' : '位置あり',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final CowStatus status;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: statusColor(status).withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    child: Text(
      status.label,
      style: TextStyle(fontWeight: FontWeight.bold, color: statusColor(status)),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon, required this.color});
  final String text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}
