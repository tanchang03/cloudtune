import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// CUE 分轨标记：`WAV · CUE 分轨`。
///
/// 描边而非填色，与曲目行的格式 chip 同一路数（理由见 `track_tile.dart`
/// 的 `_FormatChip`：一行里并排两个实心色块会互相抢）。颜色用
/// [AppTheme.cue] 这个**专供 CUE** 的值 —— 「这一组是整轨切出来的」是
/// 结构性事实，不是音质档位，借用音质家族色会让人以为它是个规格标签。
///
/// 两处用到它：分组头（列表/艺术家视图）与专辑详情页的大封面旁边。
/// 放在自己的文件里是为了让这两处用的是**同一个**标记，
/// 而不是各画一个看起来差不多的。
class CueChip extends StatelessWidget {
  const CueChip({super.key, required this.format, this.compact = false});

  /// 容器格式标签（`formatLabelOf` 的结果），如 `WAV`
  final String format;

  /// 紧凑版：分组头那一行很挤，用更小的字号与内边距
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.cue;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(compact ? 5 : 6),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$format · CUE 分轨',
        maxLines: 1,
        style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0.3,
          color: c,
        ),
      ),
    );
  }
}
