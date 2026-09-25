import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/album_cover.dart';
import '../../domain/entities/drive_provider.dart';
import '../providers/library_providers.dart';
import 'album_art.dart';

/// 专辑封面图。
///
/// 三种状态都落在同一个方框里，**布局不会因为有没有封面而变化**：
///   - 还没取到字节（正在取）→ 品牌渐变占位；
///   - 取不到（网盘没给、不是图片、网盘不支持读文件）→ 同上；
///   - 取到了 → 图片淡入盖在占位上。
///
/// 为什么用「占位常驻 + 图片淡入」而不是「二选一渲染」：后者在字节到位、
/// 但**还没解码出第一帧**的那一两帧里会是一片空白 —— 卡片墙一滚动就是
/// 满屏闪烁。让渐变占位留在底下，图片从透明淡入，全程没有空白帧。
///
/// 解码尺寸按**显示宽度**给（`cacheWidth`）：一张 3000×3000 的扫描图按原尺寸
/// 解码要占 36MB 内存，一屏 20 张就是 700MB —— 而卡片实际只有 160px 宽。
class CoverImage extends ConsumerWidget {
  const CoverImage({
    super.key,
    required this.provider,
    required this.cover,
    this.radius = 12,
    this.showBadge = false,
    this.iconRatio = 0.3,
  });

  /// 无封面时的占位配色（品牌渐变 + 角标字母）
  final DriveProvider provider;

  /// `null` 表示这张专辑没有封面 —— 直接显示占位，不发任何请求。
  final AlbumCover? cover;

  final double radius;

  /// 占位上是否显示网盘来源角标。卡片墙与详情页都是单一网盘，通常关掉。
  final bool showBadge;

  /// 占位音符相对封面的尺寸比例
  final double iconRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LayoutBuilder(
        builder: (context, box) {
          // 父级给了无限宽（比如塞进 Row）时退到一个合理默认值，
          // 否则 AlbumArt 会拿到一个 NaN 尺寸。
          final width = box.maxWidth.isFinite ? box.maxWidth : 160.0;
          final placeholder = AlbumArt(
            provider: provider,
            size: width,
            // 圆角已经在外面裁过一次，占位不必再裁
            radius: 0,
            showBadge: showBadge,
            iconSize: width * iconRatio,
          );

          final c = cover;
          if (c == null) return placeholder;

          final bytes = ref.watch(coverBytesProvider(c)).valueOrNull;
          if (bytes == null) return placeholder;

          final dpr = MediaQuery.devicePixelRatioOf(context);
          return Stack(
            fit: StackFit.expand,
            children: [
              placeholder,
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (width * dpr).round(),
                // 图片坏掉时**不要**把异常抛给全局错误处理：占位已经在底下，
                // 让它透出来就是最正确的降级（丢给全局只会在日志里刷栈，
                // 用户看到的还是一片空白）。
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
