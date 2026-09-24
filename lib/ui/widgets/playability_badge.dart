import 'package:flutter/material.dart';

import '../../domain/entities/playability.dart';
import '../theme/app_theme.dart';

/// 可播性徽标。
///
/// 只在**需要提醒**时才出现（[Playability.needsBadge]）——
/// 绝大多数曲目是可播的，给每一行都挂个「可播」标签纯属噪声。
///
/// 四个字说不清「为什么播不了」，所以传了 [onTap] 之后徽标可点，
/// 点开是完整说明（哪些文件 / 什么原因 / 什么条件才能播）。
class PlayabilityBadge extends StatelessWidget {
  const PlayabilityBadge({
    super.key,
    required this.playability,
    this.dense = false,
    this.onTap,
  });

  final Playability playability;

  /// 紧凑模式：用于列表行
  final bool dense;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!playability.needsBadge) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final color = playability.state.color(scheme);
    final message = playability.reason ?? playability.state.badgeHint;

    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        playability.state.badgeLabel,
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          height: 1.3,
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );

    if (onTap == null) {
      return Tooltip(message: message, child: pill);
    }

    return Tooltip(
      message: '$message（点击查看说明）',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill,
            const SizedBox(width: 3),
            Icon(Icons.help_outline, size: 11, color: color),
          ],
        ),
      ),
    );
  }
}
