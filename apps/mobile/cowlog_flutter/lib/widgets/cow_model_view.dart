import 'package:flutter/material.dart';

import '../models.dart';
import 'cow_avatar.dart';

/// Static transparent render of the bundled GLB; gestures belong to PageView.
class CowModelView extends StatelessWidget {
  const CowModelView({super.key, required this.style});
  final CowStyle style;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: box.maxHeight * .06,
          child: Container(
            width: box.maxWidth * .68,
            height: box.maxHeight * .10,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0x20000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        Image.asset(
          cowModelImage(style),
          width: box.maxWidth,
          height: box.maxHeight,
          fit: BoxFit.contain,
          semanticLabel: switch (style) {
            CowStyle.holstein => 'ホルスタインの牛',
            CowStyle.brown => '茶色の牛',
            CowStyle.unknown => '牛・種類未設定',
          },
        ),
      ],
    ),
  );
}
