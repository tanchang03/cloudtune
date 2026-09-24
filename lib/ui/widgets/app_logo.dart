import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'note_glyph.dart';

/// 品牌标识：圆角方块 + 品牌渐变 + 音符。
///
/// 设计原型里出现在三个地方（原型页头 34 / 侧边栏 27 / 授权页 hero 64），
/// 尺寸不同但构成一致，所以抽成一个组件按 [size] 缩放。
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 27,
    this.radius = 8,
  });

  final double size;

  /// 圆角半径。原型按 尺寸:圆角 ≈ 27:8 的比例走
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: NoteGlyph(
        // 原型 27 方块配 15 音符 ≈ 0.55
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}
