import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../state/app_store.dart';
import 'dashboard_screen.dart';
import 'herd_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _labels = ['ホーム', '優先一覧', '地図', '首輪・番号'];
  static const _icons = [
    CupertinoIcons.house_fill,
    CupertinoIcons.list_bullet,
    CupertinoIcons.map_fill,
    CupertinoIcons.slider_horizontal_3,
  ];
  static const _count = 4;

  var _index = 0;
  var _previous = 0;
  final _visited = <int>{0};
  Timer? _refreshTimer;

  /// 画面の入れ替え（0→1）。
  late final AnimationController _switch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  /// レンズの位置（タブ番号を実数で持つ。ドラッグ中は途中の値）。
  late final AnimationController _lens = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: _count - 1.0,
    value: 0,
  );

  /// 指が触れている間の膨らみ（0→1）。
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 65),
    reverseDuration: const Duration(milliseconds: 320),
  );
  double _lensFrom = 0;
  bool _dragging = false;
  int? _pressed;

  /// ドラッグ中に最後に通過したタブ（またぐたびに触覚を返す）。
  int _crossed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!widget.store.demoMode && !widget.store.isLoading) {
        widget.store.refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前面にいる間だけ自動更新する。復帰時は1回だけすぐ更新。
    if (state == AppLifecycleState.resumed) {
      if (!widget.store.demoMode) widget.store.refresh();
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _switch.dispose();
    _lens.dispose();
    _press.dispose();
    super.dispose();
  }

  void _pressDown(int? i) {
    setState(() => _pressed = i);
    _press.forward();
  }

  void _pressUp() {
    if (_pressed != null) setState(() => _pressed = null);
    _press.reverse();
  }

  void _select(int i, {bool fromDrag = false, double velocity = 0}) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    _lensFrom = _lens.value;
    if (reduced) {
      _lens.value = i.toDouble();
    } else {
      // SwiftUI の .snappy と同じばね。指を離した勢いはそのまま引き継ぐ。
      _lens.animateWith(
        SpringSimulation(
          AppleSpring.snappy,
          _lens.value,
          i.toDouble(),
          velocity,
        ),
      );
    }
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _previous = _index;
      _index = i;
      _visited.add(i);
    });
    if (reduced) {
      _switch.value = 1;
    } else {
      _switch.forward(from: 0);
    }
  }

  Widget _screen(int i) => switch (i) {
    0 => HomeScreen(store: widget.store),
    1 => DashboardScreen(store: widget.store),
    2 => MapScreen(store: widget.store),
    _ => HerdScreen(store: widget.store, active: _index == 3),
  };

  Widget _body(BuildContext context) {
    final t = Curves.easeOutCubic.transform(_switch.value);
    final moving = _switch.isAnimating;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _count; i++)
          if (_visited.contains(i))
            Offstage(
              key: ValueKey('tab-$i'),
              offstage: i != _index && !(moving && i == _previous),
              child: TickerMode(
                enabled: i == _index,
                child: IgnorePointer(
                  ignoring: i != _index,
                  child: Opacity(
                    opacity: i == _index ? t : 1 - t,
                    child: Transform.scale(
                      scale: i == _index ? 1.015 - .015 * t : 1 - .02 * t,
                      child: _screen(i),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AnimatedBuilder(
        animation: _switch,
        builder: (context, _) => _body(context),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: SizedBox(
            key: const ValueKey('app-navigation'),
            height: 66,
            child: Glass(
              radius: 33,
              padding: const EdgeInsets.all(5),
              child: LayoutBuilder(
                builder: (context, box) {
                  final segment = box.maxWidth / _count;
                  int at(double dx) =>
                      (dx / segment).floor().clamp(0, _count - 1);
                  return Listener(
                    onPointerDown: (d) => _pressDown(at(d.localPosition.dx)),
                    onPointerUp: (_) => _pressUp(),
                    onPointerCancel: (_) => _pressUp(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        _pressUp();
                        _select(at(d.localPosition.dx));
                      },
                      onTapCancel: _pressUp,
                      onHorizontalDragStart: (_) {
                        _lens.stop();
                        _dragging = true;
                        _crossed = _lens.value.round();
                        _pressDown(null);
                      },
                      onHorizontalDragUpdate: (d) {
                        final v = (_lens.value + d.delta.dx / segment).clamp(
                          0.0,
                          _count - 1.0,
                        );
                        final near = v.round();
                        if (near != _crossed) {
                          _crossed = near;
                          HapticFeedback.selectionClick();
                        }
                        _lens.value = v;
                      },
                      onHorizontalDragEnd: (d) {
                        _dragging = false;
                        _pressUp();
                        // 勢いを考慮して着地先を決める（軽く払っても次へ進む）。
                        final speed = d.velocity.pixelsPerSecond.dx / segment;
                        final target = (_lens.value + speed * .18)
                            .round()
                            .clamp(0, _count - 1);
                        _select(target, fromDrag: true, velocity: speed);
                      },
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_lens, _press]),
                        builder: (context, _) {
                          // 移動中と指が触れている間は、レンズが少し膨らむ。
                          final target = _index.toDouble();
                          final span = (target - _lensFrom).abs();
                          final progress = span == 0 || _dragging
                              ? 1.0
                              : ((_lens.value - _lensFrom).abs() / span).clamp(
                                  0.0,
                                  1.0,
                                );
                          final travel = _dragging
                              ? 1.0
                              : _lens.isAnimating
                              ? math.sin(math.pi * progress)
                              : 0.0;
                          final swell = math.max(
                            travel,
                            Curves.easeOut.transform(_press.value),
                          );
                          final stretch = travel * math.min(span, 1) * .14;
                          final scale = 1 + .20 * swell;
                          final nearest = _lens.value.round();
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left:
                                    _lens.value * segment -
                                    segment * stretch / 2,
                                top: 0,
                                bottom: 0,
                                width: segment * (1 + stretch),
                                child: Transform.scale(
                                  scale: scale,
                                  child: _Lens(lift: swell),
                                ),
                              ),
                              Row(
                                children: [
                                  for (var i = 0; i < _count; i++)
                                    Expanded(
                                      child: Semantics(
                                        button: true,
                                        selected: _index == i,
                                        label: _labels[i],
                                        excludeSemantics: true,
                                        child: _TabItem(
                                          icon: _icons[i],
                                          label: _labels[i],
                                          active: nearest == i,
                                          pressed: _pressed == i
                                              ? _press.value
                                              : 0,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // 指で触れている間・動かしている間は、レンズが
                              // 透明なガラス玉になり、下のアイコンと文字が拡大して
                              // 見える（Liquid Glass のレンズ効果）。
                              if (swell > .02)
                                Positioned(
                                  left:
                                      _lens.value * segment +
                                      segment / 2 -
                                      segment * (1 + stretch) * scale / 2,
                                  top:
                                      box.maxHeight / 2 -
                                      box.maxHeight * scale / 2,
                                  width: segment * (1 + stretch) * scale,
                                  height: box.maxHeight * scale,
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      foregroundPainter: _LensGloss(
                                        radius: 28 * scale,
                                        lift: swell,
                                      ),
                                      child: RawMagnifier(
                                        size: Size(
                                          segment * (1 + stretch) * scale,
                                          box.maxHeight * scale,
                                        ),
                                        magnificationScale: 1 + .3 * swell,
                                        decoration: MagnifierDecoration(
                                          opacity: swell.clamp(0.0, 1.0),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              28 * scale,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
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

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.pressed,
  });
  final IconData icon;
  final String label;
  final bool active;
  final double pressed;
  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.muted;
    return Transform.scale(
      scale: 1 + .08 * pressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 選択中のタブに重なる、透き通ったガラスのレンズ。
/// [lift] が大きいほど（移動中・押下中）縁の光と影が強くなる。
class _Lens extends StatelessWidget {
  const _Lens({required this.lift});
  final double lift;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          // 持ち上げている間は透明なガラスに近づく。
          Colors.white.withValues(alpha: .18 - .10 * lift),
          Colors.white.withValues(alpha: .04),
        ],
      ),
      border: Border.all(
        color: AppColors.ink.withValues(alpha: .14 + .08 * lift),
        width: 1 + .4 * lift,
      ),
      boxShadow: [
        BoxShadow(
          // 持ち上げている間の影はガラス玉の外側に描く（拡大で灰色にならないよう）。
          color: AppColors.ink.withValues(alpha: .10 * (1 - lift) * (1 - lift)),
          blurRadius: 10 + 14 * lift,
          offset: Offset(0, 2 + 4 * lift),
        ),
      ],
    ),
    child: CustomPaint(
      foregroundPainter: GlassRim(radius: 28, lift: lift),
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          widthFactor: .64,
          child: Container(
            height: 1.2,
            margin: const EdgeInsets.only(top: 1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 持ち上げたガラス玉の表面：縁の光、上部の鏡面の反射、下側のわずかな影の縁。
class _LensGloss extends CustomPainter {
  const _LensGloss({required this.radius, required this.lift});
  final double radius;
  final double lift;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // 外側だけの影（ガラス玉の上から描くので拡大に取り込まれない）。
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = AppColors.ink.withValues(alpha: .16 * lift)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14),
    );
    // 表面のごく薄い白：ガラスの存在感。
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .22 * lift),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .10 * lift),
          ],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
    // 上部の鏡面の反射（細い光の帯）。
    final gloss = Rect.fromLTWH(
      size.width * .2,
      size.height * .06,
      size.width * .6,
      size.height * .16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(gloss, Radius.circular(gloss.height)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .55 * lift),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(gloss),
    );
    GlassRim(radius: radius, lift: lift).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_LensGloss old) =>
      old.radius != radius || old.lift != lift;
}
