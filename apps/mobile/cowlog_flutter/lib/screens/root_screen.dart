import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_store.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

const _tabs = [
  (label: '優先一覧', icon: Icons.fact_check_outlined, active: Icons.fact_check),
  (label: '地図', icon: Icons.map_outlined, active: Icons.map),
  (label: '接続設定', icon: Icons.settings_outlined, active: Icons.settings),
];

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );
  var _index = 0;
  var _from = 0.0;
  var _fromStretch = 0.0;

  double get _stretch {
    final t = _motion.value;
    final pulse = math.sin(t * math.pi * 2.6) * math.sin(t * math.pi);
    return pulse * (1 - t) + _fromStretch * math.pow(1 - t, 3);
  }

  double get _position =>
      lerpDouble(_from, _index, Curves.easeOutCubic.transform(_motion.value))!;

  void _select(int index) {
    if (_index == index) return;
    HapticFeedback.selectionClick();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final previousPosition = _position;
    final previousStretch = _stretch;
    setState(() {
      _from = previousPosition;
      _fromStretch = previousStretch;
      _index = index;
    });
    if (reduceMotion) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(store: widget.store),
      MapScreen(store: widget.store),
      SettingsScreen(store: widget.store),
    ];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => Scaffold(
        extendBody: true,
        body: AnimatedBuilder(
          animation: _motion,
          child: pages[_index],
          builder: (context, child) {
            final progress = reduceMotion
                ? 1.0
                : Curves.easeOutCubic.transform(_motion.value);
            return Transform.translate(
              offset: Offset(9 * (_index - _from).sign * (1 - progress), 0),
              child: Opacity(opacity: .9 + .1 * progress, child: child),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _GlassBar(
                index: _index,
                position: () => reduceMotion ? _index.toDouble() : _position,
                stretch: () => reduceMotion ? 0 : _stretch,
                motion: _motion,
                onSelected: _select,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBar extends StatelessWidget {
  const _GlassBar({
    required this.index,
    required this.position,
    required this.stretch,
    required this.motion,
    required this.onSelected,
  });

  final int index;
  final double Function() position;
  final double Function() stretch;
  final Animation<double> motion;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(29);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .13),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .82),
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .85),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / _tabs.length;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      AnimatedBuilder(
                        animation: motion,
                        builder: (context, _) {
                          final deformation = stretch();
                          final width = (slot - 12) * (1 + deformation * .48);
                          return Positioned(
                            left: (slot * (position() + .5) - width / 2).clamp(
                              0.0,
                              constraints.maxWidth - width,
                            ),
                            top: 5 + deformation * 3,
                            bottom: 5 + deformation * 3,
                            width: width,
                            child: DecoratedBox(
                              key: const ValueKey('tab-lens'),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color.alphaBlend(
                                      scheme.primary.withValues(alpha: .08),
                                      scheme.surface,
                                    ).withValues(alpha: .86),
                                    scheme.primaryContainer.withValues(
                                      alpha: .95,
                                    ),
                                  ],
                                ),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: .22),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var tab = 0; tab < _tabs.length; tab++)
                            Expanded(
                              child: _TabButton(
                                label: _tabs[tab].label,
                                icon: tab == index
                                    ? _tabs[tab].active
                                    : _tabs[tab].icon,
                                selected: tab == index,
                                onTap: () => onSelected(tab),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
              child: AnimatedScale(
                scale: _pressed && !MediaQuery.disableAnimationsOf(context)
                    ? .91
                    : 1,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: color, size: 21),
                    const SizedBox(height: 3),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
