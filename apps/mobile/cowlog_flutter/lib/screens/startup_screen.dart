import 'package:flutter/material.dart';
import '../app_theme.dart';

/// A single, brief reveal of the approved image, independent of network loading.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, required this.child});
  final Widget child;
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _finished = false;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1450),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _finished = true);
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controller.isAnimating && !_finished) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.duration = const Duration(milliseconds: 250);
      }
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final enter = Curves.easeOutCubic.transform(
                (t / .45).clamp(0.0, 1.0),
              );
              final exit = ((t - .82) / .18).clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - exit,
                child: Material(
                  color: AppColors.background,
                  child: Stack(
                    children: [
                      Center(
                        child: Transform.translate(
                          offset: Offset(reduced ? 0 : -36 * (1 - enter), 0),
                          child: Opacity(
                            opacity: reduced ? 1 : enter,
                            child: Image.asset(
                              'assets/models/cow_holstein.png',
                              width: 260,
                              semanticLabel: 'ホルスタインの成牛',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
