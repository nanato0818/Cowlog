import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models.dart';

/// Full-body images use the bundled GLB; avatars use a dedicated portrait mesh.
String cowModelImage(CowStyle style, {bool avatar = false}) {
  final name = switch (style) {
    CowStyle.holstein => 'holstein',
    CowStyle.brown => 'brown',
    CowStyle.unknown => 'unknown',
  };
  return 'assets/models/cow_$name${avatar ? '_avatar' : ''}.png';
}

class CowAvatar extends StatelessWidget {
  const CowAvatar({super.key, required this.style, this.size = 54});
  final CowStyle style;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: switch (style) {
      CowStyle.holstein => 'ホルスタインの牛アイコン',
      CowStyle.brown => '茶色の牛アイコン',
      CowStyle.unknown => '牛アイコン・種類未設定',
    },
    child: ClipOval(
      child: ColoredBox(
        color: AppColors.surfaceHigh,
        child: Image.asset(
          cowModelImage(style, avatar: true),
          width: size,
          height: size,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}
