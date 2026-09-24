import 'package:flutter/material.dart';

/// 品牌音符图形（云韵 logo / 封面水印 / App 图标共用）。
///
/// 与设计原型 `prototype/index.html` 的 `#i-note` 完全同源：
/// 一根连笔的双八分音符 —— 两竖 + 斜连线 + 两个符头。
///
/// 原型是用 `fill` 渲染的开放路径（浏览器会隐式闭合），这里同样按填充处理，
/// 因此不依赖系统图标字体：换机器、换 Flutter 版本长相都不变。
class NoteGlyph extends StatelessWidget {
  const NoteGlyph({
    super.key,
    this.size = 16,
    this.color = Colors.white,
  });

  final double size;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _NoteGlyphPainter(color: color),
        isComplex: false,
      ),
    );
  }
}

class _NoteGlyphPainter extends CustomPainter {
  const _NoteGlyphPainter({required this.color});

  final Color color;

  /// 原型 viewBox 为 24×24，这里按同一坐标系缩放，
  /// 这样字号变化时比例不会跑偏。
  static const double _viewBox = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _viewBox;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 连线（隐式闭合后即两竖之间的符尾）：
    // (9,18) → (9,6) → (19,4) → (19,16) → 回到起点
    final beam = Path()
      ..moveTo(9 * s, 18 * s)
      ..lineTo(9 * s, 6 * s)
      ..lineTo(19 * s, 4 * s)
      ..lineTo(19 * s, 16 * s)
      ..close();
    canvas.drawPath(beam, paint);

    // 两个符头
    canvas.drawCircle(Offset(7 * s, 18 * s), 2.4 * s, paint);
    canvas.drawCircle(Offset(17 * s, 16 * s), 2.4 * s, paint);
  }

  @override
  bool shouldRepaint(covariant _NoteGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
