import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
  var _homeVisit = 0;
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
  bool _dragging = false;
  double _dragDirection = 0;
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
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (i != _pressed) setState(() => _pressed = i);
    _press.forward();
  }

  void _pressUp() => _press.reverse();

  void _finishDrag({double? velocity}) {
    if (!_dragging) return;
    _dragging = false;
    _pressUp();
    // 勢いを少し先読みする。キャンセルされた操作は元のタブへ戻す。
    final target = velocity == null
        ? _index
        : (_lens.value + velocity * .18).round().clamp(0, _count - 1);
    _select(target, velocity: velocity ?? 0);
  }

  void _select(int i, {double? velocity}) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _lens.value = i.toDouble();
    } else {
      // 連続タップでも、レンズの現在位置と速度から動きをつなぐ。
      _lens.animateWith(
        SpringSimulation(
          AppleSpring.snappy,
          _lens.value,
          i.toDouble(),
          (velocity ?? _lens.velocity).clamp(-14.0, 14.0),
        ),
      );
    }
    if (i == _index) return;
    if (velocity == null || _crossed != i) HapticFeedback.selectionClick();
    setState(() {
      // 切り替えを早い段階で取り消したときは、まだ見えている画面を残す。
      if (!_switch.isAnimating || _fade >= .5) _previous = _index;
      _index = i;
      if (i == 0) _homeVisit++;
      _visited.add(i);
    });
    if (reduced || _previous == _index) {
      _switch.value = 1;
    } else {
      _switch.forward(from: 0);
    }
  }

  Widget _screen(int i) => switch (i) {
    0 => HomeScreen(store: widget.store, visit: _homeVisit),
    1 => DashboardScreen(store: widget.store),
    2 => MapScreen(store: widget.store),
    _ => HerdScreen(store: widget.store, active: _index == 3),
  };

  double get _fade => Curves.easeOutCubic.transform(_switch.value);

  Widget _body(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in [..._visited.where((i) => i != _index), _index])
          AnimatedBuilder(
            key: ValueKey(i),
            animation: _switch,
            child: TickerMode(enabled: i == _index, child: _screen(i)),
            builder: (context, child) {
              final moving = !reduced && _switch.isAnimating;
              final fade = moving ? _fade : 1.0;
              final inactive = i != _index;
              final leaving = moving && i == _previous;
              final blocked = inactive || fade < .5;
              final blur = leaving
                  ? 9.0 * fade
                  : inactive
                  ? 0.0
                  : 9.0 * (1 - fade);
              return Offstage(
                key: ValueKey('tab-$i'),
                offstage: inactive && !leaving,
                child: ExcludeFocus(
                  excluding: blocked,
                  child: ExcludeSemantics(
                    excluding: blocked,
                    child: IgnorePointer(
                      ignoring: blocked,
                      child: Opacity(
                        opacity: inactive ? 1 : fade,
                        child: ImageFiltered(
                          enabled: blur > .1,
                          imageFilter: ImageFilter.blur(
                            sigmaX: blur,
                            sigmaY: blur,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final refreshed = CowlogUi.isRefreshed(context);
    final labels = refreshed ? const ['ホーム', '優先一覧', '地図', '設定'] : _labels;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final sideInset = refreshed ? 22.0 : 18.0;
    final navHeight = math.max(
      refreshed ? 60.0 : 66.0,
      38 + 2.2 * MediaQuery.textScalerOf(context).scale(_TabItem.labelSize),
    );
    final onMap = _index == 2;
    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _body(context),
          if (refreshed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height:
                  navHeight +
                  MediaQuery.paddingOf(context).bottom +
                  (onMap ? 32 : 50),
              child: IgnorePointer(child: _NavigationEdge(onMap: onMap)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(sideInset, 4, sideInset, 10),
          child: SizedBox(
            key: const ValueKey('app-navigation'),
            height: navHeight,
            child: Glass(
              radius: navHeight / 2,
              backingOpacity: highContrast
                  ? .85
                  : (onMap ? .62 : (refreshed ? .42 : 0)),
              padding: const EdgeInsets.all(5),
              clipContent: false,
              child: LayoutBuilder(
                builder: (context, box) {
                  final segment = box.maxWidth / _count;
                  int at(double dx) =>
                      (dx / segment).floor().clamp(0, _count - 1);
                  return Listener(
                    onPointerDown: (d) => _pressDown(at(d.localPosition.dx)),
                    onPointerUp: (_) => _pressUp(),
                    onPointerCancel: (_) {
                      // 認識済みのドラッグは、PointerCancel でも onEnd が呼ばれる。
                      _finishDrag();
                      _pressUp();
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTapUp: (d) {
                        _pressUp();
                        _select(at(d.localPosition.dx));
                      },
                      onTapCancel: _pressUp,
                      onHorizontalDragStart: (_) {
                        _lens.stop();
                        _dragging = true;
                        _dragDirection = 0;
                        _crossed = _lens.value.round();
                        _pressDown(null);
                      },
                      onHorizontalDragUpdate: (d) {
                        _dragDirection = d.delta.dx.sign;
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
                      onHorizontalDragEnd: (d) => _finishDrag(
                        velocity: d.velocity.pixelsPerSecond.dx / segment,
                      ),
                      onHorizontalDragCancel: _finishDrag,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_lens, _press]),
                        builder: (context, _) {
                          final velocity = _lens.velocity;
                          final direction = _dragging
                              ? _dragDirection
                              : velocity.sign;
                          final speed = velocity.abs();
                          final travel = reduced
                              ? 0.0
                              : _dragging
                              ? .9
                              : (speed / 9).clamp(0.0, 1.0);
                          final press = reduced
                              ? 0.0
                              : Curves.easeOut.transform(_press.value);
                          final swell = math.max(travel, press);
                          final lensHeight = box.maxHeight * (1 + .27 * swell);
                          final lensWidth =
                              segment * (1 + .20 * swell + .14 * travel);
                          final lensLeft =
                              ((_lens.value + .5) * segment - lensWidth / 2)
                                  .clamp(-4.0, box.maxWidth + 4 - lensWidth);
                          final lensTop = (box.maxHeight - lensHeight) / 2;
                          final radius = lensHeight / 2;
                          final nearest = _lens.value.round();
                          final lensRight = lensLeft + lensWidth;
                          final tailLength = math.min(
                            segment * .32 * travel,
                            direction > 0
                                ? math.max(0.0, lensLeft + 4)
                                : math.max(0.0, box.maxWidth + 4 - lensRight),
                          );
                          final overlap = radius * .75;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (direction != 0 && tailLength > 1)
                                Positioned(
                                  left: direction > 0
                                      ? lensLeft - tailLength
                                      : lensRight - overlap,
                                  top: lensTop,
                                  width: tailLength + overlap,
                                  height: lensHeight,
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      key: const ValueKey('lens-trail'),
                                      painter: _LensTrail(
                                        mirrored: direction < 0,
                                        lift: travel,
                                        overlap: overlap,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: lensLeft,
                                top: lensTop,
                                width: lensWidth,
                                height: lensHeight,
                                child: _Lens(radius: radius, lift: swell),
                              ),
                              Row(
                                children: [
                                  for (var i = 0; i < _count; i++)
                                    Expanded(
                                      child: Semantics(
                                        button: true,
                                        selected: _index == i,
                                        label: labels[i],
                                        onTap: () => _select(i),
                                        excludeSemantics: true,
                                        child: _TabItem(
                                          icon: refreshed && i == 3
                                              ? CupertinoIcons.gear_alt
                                              : _icons[i],
                                          label: labels[i],
                                          active: nearest == i,
                                          strongContrast:
                                              refreshed ||
                                              onMap ||
                                              highContrast,
                                          pressed: _pressed == i ? press : 0,
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
                                  left: lensLeft,
                                  top: lensTop,
                                  width: lensWidth,
                                  height: lensHeight,
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      foregroundPainter: _LensGloss(
                                        radius: radius,
                                        lift: swell,
                                      ),
                                      child: RawMagnifier(
                                        size: Size(lensWidth, lensHeight),
                                        magnificationScale: 1 + .3 * swell,
                                        decoration: MagnifierDecoration(
                                          opacity: swell.clamp(0.0, 1.0),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              radius,
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

/// Softens the content directly behind the floating navigation near the edge.
class _NavigationEdge extends StatelessWidget {
  const _NavigationEdge({required this.onMap});

  final bool onMap;

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.refreshCanvas;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface.withValues(alpha: 0),
            surface.withValues(alpha: onMap ? .18 : .72),
            surface.withValues(alpha: onMap ? .52 : .92),
          ],
          stops: const [0, .48, 1],
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
    required this.strongContrast,
    required this.pressed,
  });
  final IconData icon;
  final String label;
  final bool active;
  final bool strongContrast;
  static const labelSize = 11.0;
  final double pressed;
  @override
  Widget build(BuildContext context) {
    final color = active
        ? (strongContrast ? AppColors.accentDark : AppColors.accent)
        : strongContrast
        ? AppColors.ink
        : AppColors.muted;
    return Transform.scale(
      scale: 1 + .08 * pressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: labelSize,
              height: 1.1,
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
  const _Lens({required this.radius, required this.lift});
  final double radius;
  final double lift;
  @override
  Widget build(BuildContext context) {
    final refreshed = CowlogUi.isRefreshed(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // 持ち上げている間は透明なガラスに近づく。
            if (refreshed) ...[
              AppColors.ink.withValues(alpha: .07 * (1 - lift)),
              AppColors.ink.withValues(alpha: .1 * (1 - lift)),
            ] else ...[
              AppColors.surface.withValues(alpha: .18 - .10 * lift),
              AppColors.surface.withValues(alpha: .04),
            ],
          ],
        ),
        border: Border.all(
          color: AppColors.ink.withValues(
            alpha: (refreshed ? .06 : .14) + .08 * lift,
          ),
          width: (refreshed ? .7 : 1) + .4 * lift,
        ),
        boxShadow: [
          BoxShadow(
            // 持ち上げている間の影はガラス玉の外側に描く（拡大で灰色にならないよう）。
            color: AppColors.ink.withValues(
              alpha: (refreshed ? .04 : .10) * (1 - lift) * (1 - lift),
            ),
            blurRadius: 10 + 14 * lift,
            offset: Offset(0, 2 + 4 * lift),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: refreshed && lift < .02
            ? null
            : GlassRim(radius: radius, lift: lift),
        child: refreshed && lift < .02
            ? null
            : Align(
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
}

/// Slower edges stretch and taper toward the tab the lens is leaving.
class _LensTrail extends CustomPainter {
  const _LensTrail({
    required this.mirrored,
    required this.lift,
    required this.overlap,
  });

  final bool mirrored;
  final double lift;
  final double overlap;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final neck = w - overlap;
    final path = Path()
      ..moveTo(0, h * .5)
      ..cubicTo(neck * .5, h * .38, neck * .8, h * .48, w, h * .09)
      ..lineTo(w, h * .91)
      ..cubicTo(neck * .8, h * .52, neck * .5, h * .62, 0, h * .5)
      ..close();
    final bounds = Offset.zero & size;
    canvas.save();
    if (mirrored) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .6 * lift),
            Colors.white.withValues(alpha: .30 * lift),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..shader = LinearGradient(
          colors: [
            AppColors.ink.withValues(alpha: .16 * lift),
            Colors.white.withValues(alpha: .8 * lift),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LensTrail old) =>
      old.mirrored != mirrored || old.lift != lift || old.overlap != overlap;
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
            Colors.white.withValues(alpha: .15 * lift),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .08 * lift),
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
            Colors.white.withValues(alpha: .44 * lift),
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
