import 'package:flutter/material.dart';

import '../../domain/entities/drive_provider.dart';
import '../theme/app_theme.dart';
import 'note_glyph.dart';

/// 曲目封面。
///
/// 还没有接标签读取，封面图无从获取，因此按设计原型（`.cover`）的做法：
/// 用**网盘品牌渐变**打底 + 品牌音符居中 + 右下角来源角标（Q / A / B）。
///
/// 好处是「这首歌来自哪个网盘」在列表里一眼可见，且与侧边栏、来源 pill、
/// 播放器页用的是同一套颜色口径（见 [DriveProviderVisuals]）。
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.provider,
    this.size = 44,
    this.radius = 10,
    this.showBadge = true,
    this.iconSize,
    this.gradient,
  });

  /// 决定配色，同时决定右下角角标字母
  final DriveProvider provider;

  final double size;

  final double radius;

  /// 是否显示右下角来源角标（大图或播放器页可关掉）
  final bool showBadge;

  /// 音符尺寸，默认按封面尺寸的 36% 走
  final double? iconSize;

  /// 覆盖默认品牌渐变 —— 播放器页大封面用的是原型 `.p-cover`
  /// 那套蓝→紫→粉渐变，与网盘品牌色无关，所以留了这个口子。
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final compact = size < 40;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 品牌渐变底
            DecoratedBox(
              decoration: BoxDecoration(gradient: gradient ?? provider.brandGradient),
            ),
            // 左上高光：原型 `.p-cover .in` 的径向光，让封面不至于是一块死板的色块
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.45, -0.5),
                  radius: 0.95,
                  colors: [
                    Colors.white.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.62],
                ),
              ),
            ),
            Center(
              child: NoteGlyph(
                size: iconSize ?? size * 0.36,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
            if (showBadge)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 3 : 4,
                    vertical: 1,
                  ),
                  // 原型 .cover .src：rgba(0,0,0,.45)，圆角 5 0 8 0
                  decoration: BoxDecoration(
                    color: const Color(0x73000000),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(compact ? 4 : 5),
                      bottomRight: Radius.circular(radius * 0.8),
                    ),
                  ),
                  child: Text(
                    provider.badgeLetter,
                    style: TextStyle(
                      fontSize: compact ? 7 : 8,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: 0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
