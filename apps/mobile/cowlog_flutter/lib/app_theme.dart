import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;

/// コンセプト色 #D9473D を軸にした配色。地も白、カードは白＋柔らかい影
/// （ライブアクティビティ風の角の大きい小カード）。色はコンセプト色と同系色だけ。
class AppColors {
  /// 主な文字・強調の塗り。
  static const ink = Color(0xff1f1f21);

  /// 墨色の塗りの上に載せる文字。
  static const onInk = Color(0xffffffff);

  /// 地図の上に載せる暗いラベル。
  static const night = Color(0xff1f1f21);
  static const muted = Color(0xff6b6b70);
  static const faint = Color(0xffd4d4d8);
  static const background = Color(0xffffffff);

  /// カードの地。
  static const surface = Color(0xffffffff);

  /// カード内の一段沈んだ地（ゲージの下地・アイコンの丸）。
  static const surfaceHigh = Color(0xfff2f2f4);
  static const line = Color(0xffe8e8eb);

  /// ホーム上半分の背景。
  static const stageTop = Color(0xffffffff);
  static const stageBottom = Color(0xffffffff);

  /// カードの柔らかい影。
  static const cardShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 22, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// コンセプト色。
  static const accent = Color(0xffd9473d);
  static const accentDark = Color(0xffb02a21);
  static const accentSoft = Color(0xfffbe9e7);
  static const glowA = Color(0xffe8665b);
  static const glowB = Color(0xffc93a31);

  /// スイッチのオフ色と、航空写真上のラベルの背景・影。
  static const switchOff = Color(0xffe5e5ea);
  static const switchMapSurface = Color(0xf5ffffff);
  static const switchMapShadow = Color(0x47000000);

  /// グラフ：コンセプト色の同系色でまとめる。
  static const ringActive = accent;
  static const ringInactive = Color(0xfff0c3b7);
  static const ringTrack = surfaceHigh;
  static const barIdle = Color(0xffeadfd9);

  /// 刷新版の情報面と操作部の色。
  static const refreshCanvas = Color(0xfff3f4f6);
  static const refreshStageEdge = Color(0xffe9ebee);
  static const refreshDivider = Color(0xffe1e4e8);
  static const refreshGlass = Color(0xfff8f9fa);

  /// 区画線（仕様の黄色系を維持）。
  static const boundary = Color(0xffc69650);

  static const glow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [glowA, glowB],
  );
}

/// The app keeps the current layout as the default while the refresh is reviewed.
class CowlogUi extends InheritedWidget {
  const CowlogUi({super.key, required this.refreshed, required super.child});

  final bool refreshed;

  static bool isRefreshed(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CowlogUi>()?.refreshed ??
      false;

  static BoxDecoration panel({double radius = 22}) => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.refreshDivider),
  );

  @override
  bool updateShouldNotify(CowlogUi oldWidget) =>
      refreshed != oldWidget.refreshed;
}

/// 桁がずれない数字。番号・％・時刻に使う。
const tabularFigures = [FontFeature.tabularFigures()];

/// SwiftUI の標準のばね（.snappy / .smooth / .bouncy）と同じ値。
/// response（秒）から剛性を求める：stiffness = (2π / response)²。
class AppleSpring {
  static SpringDescription _of(double response, double damping) =>
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: math.pow(2 * math.pi / response, 2).toDouble(),
        ratio: damping,
      );

  /// 素早く、わずかに弾む（タブのレンズ）。
  static final snappy = _of(.4, .85);

  /// 弾まずになめらか。
  static final smooth = _of(.5, 1);

  /// はっきり弾む。
  static final bouncy = _of(.5, .7);
}

/// iOS標準に近い、わずかに弾むカーブ。
const springCurve = Cubic(.3, 1.28, .6, 1);

/// 彩度を約1.6倍にする行列（背景の色を澄ませる）。
const _saturate = <double>[
  1.36, -.32, -.04, 0, 0, //
  -.10, 1.18, -.04, 0, 0, //
  -.10, -.32, 1.48, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// A light halo keeps dark labels legible over detailed aerial imagery.
const glassContentShadows = [Shadow(color: Color(0xe6ffffff), blurRadius: 3)];

/// 背後をぼかす透き通ったガラス面。地図や一覧の上に重ねる部品専用。
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    this.lift = 0,
    this.backingOpacity = 0,
    this.clipContent = true,
    this.tinted = false,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool shadow;
  final bool tinted;

  /// 押している間の持ち上がり（0〜1）。縁の光と表面の白が強くなる。
  final double lift;

  /// 写真など複雑な背景で、前景のコントラストを保つために足す白。
  final double backingOpacity;

  /// The navigation lens can rise above the capsule while the glass stays clipped.
  final bool clipContent;

  double _surfaceAlpha(double alpha, double tintedMinimum) => math.max(
    alpha + backingOpacity * (1 - alpha),
    tinted ? tintedMinimum : 0,
  );

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final surface = tinted ? AppColors.refreshGlass : AppColors.surface;
    final content = Padding(
      padding: padding,
      child: DefaultTextStyle.merge(
        style: const TextStyle(shadows: glassContentShadows),
        child: IconTheme.merge(
          data: const IconThemeData(shadows: glassContentShadows),
          child: child,
        ),
      ),
    );
    final backdrop = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            inner: ImageFilter.matrix(
              (Matrix4.identity()..setTranslationRaw(.6, -.4, 0)).storage,
            ),
          ),
          inner: const ColorFilter.matrix(_saturate),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surface.withValues(alpha: _surfaceAlpha(.14 + .16 * lift, .86)),
                surface.withValues(alpha: _surfaceAlpha(.05 + .06 * lift, .68)),
              ],
            ),
            border: Border.all(
              color: AppColors.ink.withValues(alpha: .16),
              width: 1,
            ),
          ),
          child: CustomPaint(
            foregroundPainter: GlassRim(radius: radius, lift: lift),
            child: clipContent ? content : const SizedBox.expand(),
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x1f000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: clipContent
          ? backdrop
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: backdrop),
                content,
              ],
            ),
    );
  }
}

/// A fine continuous rim, bright at the top and subtly dark underneath.
class GlassRim extends CustomPainter {
  const GlassRim({required this.radius, this.lift = 0});
  final double radius;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: .85 + .15 * lift),
          Colors.white.withValues(alpha: .12),
          AppColors.ink.withValues(alpha: .18),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.5), Radius.circular(radius)),
      paint,
    );
    paint
      ..strokeWidth = .6
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withValues(alpha: .22), Colors.transparent],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(radius - 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(GlassRim oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.lift != lift;
}

/// 状態ラベル。要確認だけ墨色の塗り、それ以外は文字のみ。
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.text, required this.urgent});
  final String text;
  final bool urgent;
  @override
  Widget build(BuildContext context) => Container(
    padding: urgent
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
        : EdgeInsets.zero,
    decoration: urgent
        ? BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(99),
          )
        : null,
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: urgent ? AppColors.onInk : AppColors.muted,
      ),
    ),
  );
}

/// 選択できる小さなピル。選択中は墨色。
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 40),
        padding: EdgeInsets.fromLTRB(leading == null ? 14 : 8, 6, 14, 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularFigures,
                color: selected ? AppColors.onInk : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'DEMO',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: AppColors.muted,
      ),
    ),
  );
}

/// 通信不良・エラーの短い表示。
class NoticeBadge extends StatelessWidget {
  const NoticeBadge({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.onInk,
      ),
    ),
  );
}

/// ライブアクティビティ風の小カード。左上に色付きアイコンと小さな見出し、
/// 右上に補助の値。淡い地の上に角の大きい白い面で置く。
class LiveCard extends StatelessWidget {
  const LiveCard({
    super.key,
    required this.child,
    this.icon,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
  });
  final Widget child;
  final IconData? icon;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final refreshed = CowlogUi.isRefreshed(context);
    return Container(
      padding: padding,
      decoration: refreshed
          ? CowlogUi.panel()
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppColors.cardShadow,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Apple の文字サイズ規則の Subheadline（15pt）を太めに。
                    style: TextStyle(
                      fontSize: refreshed ? 17 : 15,
                      fontWeight: refreshed ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: -.2,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// 押すと少し縮み、離すとばねで戻る（iOS標準アプリの押下の手応え）。
/// 縮むときは SwiftUI の .snappy、戻るときは少し弾む .bouncy と同じばね。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = .96,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  void _to(double v, SpringDescription spring) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = v;
      return;
    }
    _c.animateWith(SpringSimulation(spring, _c.value, v, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Listener(
      onPointerDown: enabled ? (_) => _to(1, AppleSpring.snappy) : null,
      onPointerUp: enabled ? (_) => _to(0, AppleSpring.bouncy) : null,
      onPointerCancel: enabled ? (_) => _to(0, AppleSpring.bouncy) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.scale(
            scale: MediaQuery.disableAnimationsOf(context)
                ? 1
                : 1 - (1 - widget.scale) * _c.value,
            transformHitTests: false,
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 押すとガラスがふくらみ、縁が光るボタン
/// （SwiftUI の .glassEffect(.regular.interactive()) に相当）。
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
    this.radius = 23,
    this.padding = EdgeInsets.zero,
    this.size,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Size? size;
  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  void _to(double v, SpringDescription spring) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = v;
      return;
    }
    _c.animateWith(SpringSimulation(spring, _c.value, v, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final refreshed = CowlogUi.isRefreshed(context);
    Widget button = Listener(
      onPointerDown: enabled ? (_) => _to(1, AppleSpring.snappy) : null,
      onPointerUp: enabled ? (_) => _to(0, AppleSpring.bouncy) : null,
      onPointerCancel: enabled ? (_) => _to(0, AppleSpring.bouncy) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final v = _c.value.clamp(0.0, 1.2);
            return Transform.scale(
              scale: MediaQuery.disableAnimationsOf(context) ? 1 : 1 + .12 * v,
              transformHitTests: false,
              child: Glass(
                radius: widget.radius,
                tinted: refreshed,
                padding: widget.padding,
                lift: v.clamp(0.0, 1.0),
                child: child!,
              ),
            );
          },
          child: widget.size == null
              ? widget.child
              : SizedBox.fromSize(
                  size: widget.size,
                  child: Center(child: widget.child),
                ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        excludeFromSemantics: refreshed,
        child: button,
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: button,
    );
  }
}
