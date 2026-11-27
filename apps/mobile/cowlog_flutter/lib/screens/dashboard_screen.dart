import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../widgets/liquid_switch.dart';
import '../widgets/cow_avatar.dart';
import '../models.dart';
import '../state/app_store.dart';
import 'detail_screen.dart';

String dateTimeLabel(DateTime v) =>
    '${v.month}/${v.day} ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _query = '';
  CowStatus? _status;
  bool _positionOnly = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final store = widget.store;
    final all = store.dashboard?.cows ?? <Cow>[];
    final cows = all
        .where(
          (c) =>
              c.displayNumber.contains(_query) &&
              (_status == null || c.status == _status) &&
              (!_positionOnly || (c.latestPosition?.isUsable ?? false)),
        )
        .toList();
    final notice = store.isOffline ? 'オフライン' : store.errorMessage;
    final refreshed = CowlogUi.isRefreshed(context);
    final controls = <Widget>[
      Row(
        children: [
          Expanded(
            child: TextField(
              keyboardType: TextInputType.number,
              style: const TextStyle(
                fontSize: 17,
                fontFeatures: tabularFigures,
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(CupertinoIcons.search, size: 22),
                hintText: '番号で検索',
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          if (store.demoMode) ...[const SizedBox(width: 8), const DemoBadge()],
          IconButton(
            tooltip: '更新',
            onPressed: store.isLoading ? null : store.refresh,
            icon: const Icon(CupertinoIcons.arrow_clockwise, size: 24),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: refreshed ? 44 : 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Pill(
                label: 'すべて',
                selected: _status == null,
                onTap: () => setState(() => _status = null),
              ),
            ),
            for (final s in CowStatus.values)
              if (s != CowStatus.unknown || all.any((c) => c.status == s))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Pill(
                    label:
                        '${s.label} ${all.where((c) => c.status == s).length}',
                    selected: _status == s,
                    onTap: () =>
                        setState(() => _status = _status == s ? null : s),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Text(
            '${cows.length} / ${all.length}頭',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              fontFeatures: tabularFigures,
            ),
          ),
          if (notice != null) ...[
            const SizedBox(width: 10),
            Flexible(child: NoticeBadge(text: notice)),
          ],
          const Spacer(),
          LiquidSwitch(
            label: '位置あり',
            value: _positionOnly,
            onChanged: (value) => setState(() => _positionOnly = value),
          ),
        ],
      ),
    ];
    return Material(
      color: refreshed ? AppColors.refreshCanvas : AppColors.background,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ink,
          backgroundColor: AppColors.surface,
          onRefresh: store.refresh,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, refreshed ? 14 : 4, 20, 140),
            children: [
              if (refreshed)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  decoration: CowlogUi.panel(),
                  child: Column(children: controls),
                )
              else
                ...controls,
              SizedBox(height: refreshed ? 14 : 8),
              if (store.isLoading && all.isEmpty)
                for (var i = 0; i < 4; i++) const _CardPlaceholder(),
              if (cows.isEmpty && !store.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      '該当なし',
                      style: TextStyle(fontSize: 15, color: AppColors.muted),
                    ),
                  ),
                ),
              for (final cow in cows)
                CowCard(
                  cow: cow,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(store: store, cow: cow),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    height: 90,
    margin: const EdgeInsets.symmetric(vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(28),
    ),
  );
}

class CowCard extends StatelessWidget {
  const CowCard({super.key, required this.cow, required this.onTap});
  final Cow cow;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final refreshed = CowlogUi.isRefreshed(context);
    return Pressable(
      onTap: onTap,
      scale: .97,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
          child: Row(
            children: [
              CowAvatar(style: cow.style),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cow.displayNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: refreshed ? 27 : 25,
                        fontWeight: refreshed
                            ? FontWeight.w700
                            : FontWeight.w600,
                        letterSpacing: -.4,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cow.latestMeasuredAt == null
                          ? '未受信'
                          : dateTimeLabel(cow.latestMeasuredAt!),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusLabel(
                    text: cow.status.label,
                    urgent:
                        cow.status == CowStatus.check ||
                        cow.status == CowStatus.unknown,
                  ),
                  if (cow.batteryPercent != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.battery_75_percent,
                            size: 15,
                            color: cow.batteryPercent! <= 30
                                ? AppColors.accent
                                : AppColors.muted,
                          ),
                          Text(
                            '${cow.batteryPercent}%',
                            style: TextStyle(
                              fontSize: 13,
                              color: cow.batteryPercent! <= 30
                                  ? AppColors.accent
                                  : AppColors.muted,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_right,
                size: refreshed ? 17 : 22,
                color: refreshed ? AppColors.muted : AppColors.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
