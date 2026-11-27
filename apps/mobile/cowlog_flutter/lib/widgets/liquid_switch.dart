import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../app_theme.dart';

/// A labeled switch with a solid thumb at rest and a lens while held.
class LiquidSwitch extends StatefulWidget {
  const LiquidSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onImagery = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Gives the label and switch a legible surface above a map or photograph.
  final bool onImagery;

  @override
  State<LiquidSwitch> createState() => _LiquidSwitchState();
}

class _LiquidSwitchState extends State<LiquidSwitch>
    with TickerProviderStateMixin {
  static const _travel = 22.0;
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: _restingPosition,
  );
  late final AnimationController _lift = AnimationController.unbounded(
    vsync: this,
  );
  late final Listenable _animation = Listenable.merge([_position, _lift]);
  double? _dragPosition;
  int? _pointer;
  bool _pointerCancelled = false;
  bool _reduceMotion = false;

  double get _restingPosition => widget.value ? 1 : 0;
  double get _direction =>
      Directionality.of(context) == TextDirection.ltr ? 1 : -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _lift.value = 0;
      _position.value = _restingPosition;
    }
  }

  @override
  void didUpdateWidget(covariant LiquidSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _dragPosition == null) {
      _settlePosition();
    }
  }

  void _settlePosition() {
    if (_reduceMotion) {
      _position.value = _restingPosition;
    } else if (_position.value != _restingPosition || _position.isAnimating) {
      _position.animateWith(
        SpringSimulation(
          AppleSpring.snappy,
          _position.value,
          _restingPosition,
          _position.velocity,
        ),
      );
    }
  }

  void _press(PointerDownEvent event) {
    if (_pointer != null || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _pointerCancelled = false;
    if (!_reduceMotion) {
      _lift.animateTo(
        1,
        duration: const Duration(milliseconds: 115),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _release(PointerEvent event) {
    if (event.pointer == _pointer) _releasePress();
  }

  void _cancelPointer(PointerCancelEvent event) {
    if (event.pointer == _pointer) {
      // Flutter can report onDragEnd for a cancelled, accepted drag.
      _pointerCancelled = true;
      _releasePress();
    }
  }

  void _releasePress() {
    if (_pointer == null) return;
    _pointer = null;
    if (!_reduceMotion) {
      _lift.animateWith(
        SpringSimulation(AppleSpring.bouncy, _lift.value, 0, 0),
      );
    }
  }

  void _toggle() => widget.onChanged(!widget.value);

  void _startDrag(DragStartDetails details) {
    _dragPosition = _position.value.clamp(0, 1);
    _position.stop();
  }

  void _updateDrag(DragUpdateDetails details) {
    final next = _dragPosition! + details.delta.dx * _direction / _travel;
    _dragPosition = next.clamp(-.35, 1.35);
    if (!_reduceMotion) _position.value = _dragPosition!;
  }

  void _endDrag(DragEndDetails details) {
    final next = _dragPosition! >= .5;
    _cancelDrag();
    if (!_pointerCancelled && next != widget.value) widget.onChanged(next);
  }

  void _cancelDrag() {
    final wasDragging = _dragPosition != null;
    _dragPosition = null;
    _releasePress();
    if (wasDragging) _settlePosition();
  }

  @override
  void dispose() {
    _position.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = _direction < 0;
    return Semantics(
      label: widget.label,
      toggled: widget.value,
      onTap: _toggle,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: _press,
        onPointerUp: _release,
        onPointerCancel: _cancelPointer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          dragStartBehavior: DragStartBehavior.down,
          onTap: _toggle,
          onHorizontalDragStart: _startDrag,
          onHorizontalDragUpdate: _updateDrag,
          onHorizontalDragEnd: _endDrag,
          onHorizontalDragCancel: _cancelDrag,
          child: DecoratedBox(
            decoration: widget.onImagery
                ? const ShapeDecoration(
                    color: AppColors.switchMapSurface,
                    shape: StadiumBorder(),
                    shadows: [
                      BoxShadow(
                        color: AppColors.switchMapShadow,
                        blurRadius: 9,
                        offset: Offset(0, 2),
                      ),
                    ],
                  )
                : const BoxDecoration(),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: widget.onImagery ? 12 : 0,
                end: widget.onImagery ? 4 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => _SwitchVisual(
                      position: _position.value,
                      lift: _lift.value.clamp(-.12, 1.05),
                      isRtl: isRtl,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchVisual extends StatelessWidget {
  const _SwitchVisual({
    required this.position,
    required this.lift,
    required this.isRtl,
  });

  final double position;
  final double lift;
  final bool isRtl;

  static const _capsule = StadiumBorder();
  static const _trackSize = Size(62, 28);

  @override
  Widget build(BuildContext context) {
    final fraction = position.clamp(0.0, 1.0);
    final glass = lift.clamp(0.0, 1.0);
    final stretch = 1 - (2 * fraction - 1).abs();
    final thumbSize = Size(
      38 + 14 * lift + 5 * glass * stretch,
      24 + 14 * lift - 2 * glass * stretch,
    );
    final thumbCenter =
        35 +
        (isRtl ? -1 : 1) * (22 * (fraction - .5) + 9 * (position - fraction));
    final trackProgress = ((fraction - .3) / .4).clamp(0.0, 1.0);
    final trackColor = Color.lerp(
      AppColors.switchOff,
      AppColors.accent,
      trackProgress,
    )!;
    return SizedBox(
      width: 70,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox.fromSize(
            size: _trackSize,
            child: DecoratedBox(
              decoration: ShapeDecoration(color: trackColor, shape: _capsule),
            ),
          ),
          Positioned(
            left: thumbCenter - thumbSize.width / 2,
            top: (44 - thumbSize.height) / 2,
            width: thumbSize.width,
            height: thumbSize.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (glass > 0)
                  RawMagnifier(
                    size: thumbSize,
                    // The track looks narrower through the raised lens.
                    magnificationScale: 1 - .18 * glass,
                    focalPointOffset: Offset(0, .6 * glass),
                    decoration: MagnifierDecoration(
                      shape: _capsule,
                      shadows: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: .14 * glass),
                          blurRadius: 7 * glass,
                          blurStyle: BlurStyle.outer,
                        ),
                      ],
                    ),
                  ),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: AppColors.surface.withValues(
                      alpha: lerpDouble(1, .035, glass)!,
                    ),
                    shape: _capsule,
                    shadows: [
                      BoxShadow(
                        color: AppColors.ink.withValues(
                          alpha: .16 * (1 - glass),
                        ),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                        blurStyle: BlurStyle.outer,
                      ),
                    ],
                  ),
                ),
                if (glass > 0)
                  CustomPaint(painter: _LensRim(glass, trackColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LensRim extends CustomPainter {
  const _LensRim(this.strength, this.trackColor);

  final double strength;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(
      rect.deflate(.9),
      Radius.circular(size.height / 2),
    );
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppColors.surface.withValues(alpha: .9 * strength),
        Color.lerp(
          AppColors.ink,
          trackColor,
          .38,
        )!.withValues(alpha: .22 * strength),
        AppColors.surface.withValues(alpha: .72 * strength),
      ],
      stops: const [0, .48, 1],
    ).createShader(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..shader = gradient
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1);
    canvas.drawRRect(edge, paint);
    paint
      ..strokeWidth = .7
      ..maskFilter = null;
    canvas.drawRRect(edge, paint);
  }

  @override
  bool shouldRepaint(_LensRim oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.trackColor != trackColor;
}
